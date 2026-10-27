const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const {
  onDocumentCreated,
  onDocumentWritten,
  onDocumentWrittenWithAuthContext,
} = require("firebase-functions/v2/firestore");
const crypto = require("crypto");
const { defineSecret } = require("firebase-functions/params");
const functions = require("firebase-functions/v1");

// Init
admin.initializeApp();
const db = admin.firestore();

// Region (promijeni ako ti je drugi)
setGlobalOptions({ region: "europe-west1" });


const IDENTITY_TOOLKIT_API_KEY = defineSecret("IDENTITY_TOOLKIT_API_KEY");

/**
 * Callable: createEmployee
 *
 * request.data:
 *  {
 *    email: string,
 *    name?: string,
 *    surname?: string,
 *    username?: string
 *  }
 *
 * Preconditions:
 *  - Caller must be logged in
 *  - Caller must exist in Firestore users/{callerUid}
 *  - Caller role must be "ORG_OWNER"
 *  - Caller must have orgId
 */
exports.createEmployee = onCall({ secrets: [IDENTITY_TOOLKIT_API_KEY] }, async (request) => {
  // 1) auth check
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Moraš biti ulogovan.");
  }

  const callerUid = request.auth.uid;

  // 2) input validation
  const { email, name, surname, username } = request.data || {};
  if (!email || typeof email !== "string") {
    throw new HttpsError("invalid-argument", "Email je obavezan.");
  }
  const normalizedEmail = email.trim().toLowerCase();

  // 3) load caller user document to determine org + role
  const callerSnap = await db.collection("users").doc(callerUid).get();
  if (!callerSnap.exists) {
    throw new HttpsError(
      "permission-denied",
      "Caller user ne postoji u Firestore (users/{uid})."
    );
  }

  const callerUser = callerSnap.data();

  if (!callerUser?.isActive) {
    throw new HttpsError("permission-denied", "Nalog nije aktivan.");
  }
  if (callerUser?.role !== "ORG_OWNER") {
    throw new HttpsError("permission-denied", "Samo ORG_OWNER može dodavati zaposlene.");
  }
  const orgId = callerUser?.orgId;
  if (!orgId) {
    throw new HttpsError("failed-precondition", "Admin nema orgId u svom users dokumentu.");
  }

  // 4) Create Firebase Auth user (no password)
  let createdAuthUser;
  try {
    createdAuthUser = await admin.auth().createUser({
      email: normalizedEmail,
      displayName: `${name || ""} ${surname || ""}`.trim(),
      disabled: false,
    });
  } catch (e) {
    if (e?.code === "auth/email-already-exists") {
      // Ako je ranije obrisan (soft delete) zaposleni iz iste organizacije -> reaktiviraj ga
      return reactivateEmployee({
        email: normalizedEmail,
        name,
        surname,
        username,
        orgId,
        callerUid,
      });
    }
    throw new HttpsError("internal", `Ne mogu kreirati Auth user-a: ${e.message}`);
  }

  const employeeUid = createdAuthUser.uid;

  // 5) Set custom claims (recommended for rules / multi-tenant)
  try {
    await admin.auth().setCustomUserClaims(employeeUid, {
      role: "ORG_EMPLOYEE",
      orgId: orgId,
    });
  } catch (e) {
    // cleanup if claim fails
    await admin.auth().deleteUser(employeeUid);
    throw new HttpsError("internal", `Ne mogu postaviti custom claims: ${e.message}`);
  }

  // 6) Write Firestore users/{uid}
  const userDoc = {
    email: normalizedEmail,
    isActive: true,
    name: name || "",
    surname: surname || "",
    username: username || "",
    orgId: orgId,
    role: "ORG_EMPLOYEE",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: callerUid,
  };

  try {
    await db.collection("users").doc(employeeUid).set(userDoc, { merge: true });
  } catch (e) {
    // cleanup if firestore write fails
    await admin.auth().deleteUser(employeeUid);
    throw new HttpsError("internal", `Ne mogu upisati user-a u Firestore: ${e.message}`);
  }

  // 7) Generate password reset link
  // let resetLink;
  // try {
  //   // Ako želiš da nakon reseta vodi na tvoj web/dynamic link, možeš dodati actionCodeSettings:
  //   // const actionCodeSettings = { url: "https://tvoj-domain.com/after-reset" };
  //   // resetLink = await admin.auth().generatePasswordResetLink(normalizedEmail, actionCodeSettings);

  //   resetLink = await admin.auth().generatePasswordResetLink(normalizedEmail);
  // } catch (e) {
  //   throw new HttpsError("internal", `Ne mogu generisati reset link: ${e.message}`);
  // }

  return {
    ok: true,
    uid: employeeUid,
    orgId: orgId,
    user: userDoc
  };
});


/**
 * Reaktivira prethodno obrisanog (isActive=false) zaposlenog iz iste organizacije.
 * Ako korisnik pripada drugoj organizaciji ili je aktivan -> already-exists.
 */
async function reactivateEmployee({ email, name, surname, username, orgId, callerUid }) {
  const alreadyExists = new HttpsError("already-exists", "Korisnik sa ovim emailom već postoji.");

  let existingAuthUser;
  try {
    existingAuthUser = await admin.auth().getUserByEmail(email);
  } catch (e) {
    throw alreadyExists;
  }

  const employeeUid = existingAuthUser.uid;
  const employeeRef = db.collection("users").doc(employeeUid);
  const employeeSnap = await employeeRef.get();
  const employee = employeeSnap.data();

  if (!employeeSnap.exists || employee?.orgId !== orgId || employee?.isActive !== false) {
    throw alreadyExists;
  }

  try {
    await admin.auth().updateUser(employeeUid, {
      displayName: `${name || ""} ${surname || ""}`.trim(),
      disabled: false,
    });
    await admin.auth().setCustomUserClaims(employeeUid, {
      role: "ORG_EMPLOYEE",
      orgId: orgId,
    });
  } catch (e) {
    throw new HttpsError("internal", `Ne mogu reaktivirati Auth user-a: ${e.message}`);
  }

  const userDoc = {
    email: email,
    isActive: true,
    name: name || "",
    surname: surname || "",
    username: username || "",
    orgId: orgId,
    role: "ORG_EMPLOYEE",
    reactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
    reactivatedBy: callerUid,
  };

  try {
    await employeeRef.set(
      {
        ...userDoc,
        deletedAt: admin.firestore.FieldValue.delete(),
        deletedBy: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );
  } catch (e) {
    // vrati Auth u disabled stanje da ostane konzistentno sa Firestore-om
    await admin.auth().updateUser(employeeUid, { disabled: true });
    throw new HttpsError("internal", `Ne mogu upisati user-a u Firestore: ${e.message}`);
  }

  // onCreate trigger se ne okida za postojećeg usera, pa reset email šaljemo ovdje
  await sendPasswordResetEmail(email, IDENTITY_TOOLKIT_API_KEY.value());

  return {
    ok: true,
    uid: employeeUid,
    orgId: orgId,
    user: userDoc,
  };
}

async function sendPasswordResetEmail(email, apiKey) {
  try {
    const url = `https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${apiKey}`;

    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        requestType: "PASSWORD_RESET",
        email,
      }),
    });

    if (!resp.ok) {
      const txt = await resp.text();
      console.error(`sendOobCode failed: ${resp.status} ${txt}`);
    } else {
      console.log(`Reset password email sent to: ${email}`);
    }
  } catch (e) {
    console.error("Reset password email error:", e);
  }
}


//Soft Delte Emplyee func

exports.deleteEmployee = onCall(async (request) => {
  // 1) auth check
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Moraš biti ulogovan.");
  }

  const callerUid = request.auth.uid;

  // 2) input validation
  const { employeeUid } = request.data || {};
  if (!employeeUid || typeof employeeUid !== "string") {
    throw new HttpsError("invalid-argument", "employeeUid je obavezan.");
  }

  if (employeeUid === callerUid) {
    throw new HttpsError("failed-precondition", "Ne možeš deaktivirati sam sebe.");
  }

  // 3) load caller user (to determine org + role)
  const callerSnap = await db.collection("users").doc(callerUid).get();
  if (!callerSnap.exists) {
    throw new HttpsError(
      "permission-denied",
      "Caller user ne postoji u Firestore (users/{uid})."
    );
  }

  const callerUser = callerSnap.data();

  if (!callerUser?.isActive) {
    throw new HttpsError("permission-denied", "Nalog nije aktivan.");
  }

  if (callerUser?.role !== "ORG_OWNER") {
    throw new HttpsError(
      "permission-denied",
      "Samo ORG_OWNER može brisati (deaktivirati) zaposlene."
    );
  }

  const orgId = callerUser?.orgId;
  if (!orgId) {
    throw new HttpsError(
      "failed-precondition",
      "Admin nema orgId u svom users dokumentu."
    );
  }

  // 4) load target employee doc and validate org
  const employeeRef = db.collection("users").doc(employeeUid);
  const employeeSnap = await employeeRef.get();

  if (!employeeSnap.exists) {
    throw new HttpsError("not-found", "Korisnik ne postoji.");
  }

  const employee = employeeSnap.data();

  // Multi-tenant zaštita
  if (employee?.orgId !== orgId) {
    throw new HttpsError(
      "permission-denied",
      "Ne možeš deaktivirati korisnika iz druge organizacije."
    );
  }

  // (opciono) samo zaposlene
  // if (employee?.role !== "ORG_EMPLOYEE") {
  //   throw new HttpsError(
  //     "failed-precondition",
  //     "Možeš deaktivirati samo ORG_EMPLOYEE korisnike."
  //   );
  // }

  // 5) disable in Firebase Auth
  try {
    await admin.auth().updateUser(employeeUid, { disabled: true });
  } catch (e) {
    throw new HttpsError(
      "internal",
      `Ne mogu disable-ovati Auth korisnika: ${e.message}`
    );
  }

  // 6) update Firestore isActive=false
  try {
    await employeeRef.set(
      {
        isActive: false,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedBy: callerUid,
      },
      { merge: true }
    );
  } catch (e) {
    // Auth je već disabled; možeš odlučiti da li želiš rollback (nije preporučeno)
    throw new HttpsError(
      "internal",
      `Auth disabled, ali ne mogu upisati u Firestore: ${e.message}`
    );
  }

  return {
    ok: true,
    employeeUid,
    orgId,
  };
});


exports.sendResetPasswordOnAuthCreate = functions
  .region("europe-west1")
  .runWith({ secrets: [IDENTITY_TOOLKIT_API_KEY] })
  .auth.user()
  .onCreate(async (user) => {
    try {
      if (!user?.email) return null;

      const email = user.email.trim().toLowerCase();
      await sendPasswordResetEmail(email, IDENTITY_TOOLKIT_API_KEY.value());

      return null;
    } catch (e) {
      console.error("Reset password email error:", e);
      return null;
    }
  });


// ---------------------------------------------------------------------------
// Push notifikacije za termine
// ---------------------------------------------------------------------------

const PUSH_TOKENS_COLLECTION = "pushTokens";
const SLOT_TIME_ZONE = "Europe/Sarajevo";

// Promjena nekog od ovih polja je bitna zaposlenima (napomena nije).
const SLOT_NOTIFY_FIELDS = [
  "startDateTime",
  "endDateTime",
  "employeeIds",
  "clientId",
  "serviceIds",
];

const SLOT_NOTIFICATION_TITLES = {
  created: "Novi termin",
  updated: "Termin izmijenjen",
  deleted: "Termin otkazan",
};

const INVALID_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

// "{username} je dodao termin za tebe na dan 10.10.2026 u 16h"
const SLOT_NOTIFICATION_ACTIONS = {
  created: "je dodao termin",
  updated: "je izmijenio termin",
  deleted: "je otkazao termin",
};

// Kad nije poznato ko je napravio promjenu.
const SLOT_NOTIFICATION_ACTIONS_WITHOUT_ACTOR = {
  created: "Dodat je termin",
  updated: "Izmijenjen je termin",
  deleted: "Otkazan je termin",
};

// Token je predug i ima znakove nepogodne za id dokumenta, pa koristimo hash.
// Isti uređaj uvijek pogađa isti dokument, pa kad se na uređaju prijavi drugi
// korisnik, token se automatski prebaci na njega.
function pushTokenRef(token) {
  const id = crypto.createHash("sha256").update(token).digest("hex");
  return db.collection(PUSH_TOKENS_COLLECTION).doc(id);
}

function readToken(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Moraš biti ulogovan.");
  }

  const { token } = request.data || {};
  if (!token || typeof token !== "string" || token.length > 4096) {
    throw new HttpsError("invalid-argument", "token je obavezan.");
  }

  return token;
}

exports.registerPushToken = onCall(async (request) => {
  const token = readToken(request);
  const uid = request.auth.uid;

  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.data();
  if (!userSnap.exists || !user?.orgId || user?.isActive === false) {
    throw new HttpsError("permission-denied", "Nalog nije aktivan.");
  }

  await pushTokenRef(token).set({
    token,
    uid,
    orgId: user.orgId,
    platform: request.data?.platform === "ios" ? "ios" : "android",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true };
});

exports.unregisterPushToken = onCall(async (request) => {
  const token = readToken(request);

  const ref = pushTokenRef(token);
  const snap = await ref.get();
  if (snap.exists && snap.data()?.uid === request.auth.uid) {
    await ref.delete();
  }

  return { ok: true };
});

// Tipovi tipa principala za server i sistem; sve ostalo je korisnik aplikacije.
const NON_USER_AUTH_TYPES = new Set([
  "service_account",
  "api_key",
  "system",
  "unauthenticated",
  "unknown",
]);

/**
 * Obavještava zaposlene na terminu kad se termin doda, izmijeni ili obriše.
 * Korisnik koji je napravio promjenu ne dobija notifikaciju. Ko je to,
 * Firestore javlja kroz auth context, pa radi i za starije verzije
 * aplikacije; lastModifiedBy / deletedBy su rezerva.
 */
exports.notifySlotChange = onDocumentWrittenWithAuthContext(
  "organizations/{orgId}/slots/{slotId}",
  async (event) => {
    const { orgId, slotId } = event.params;
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    const authUid =
      event.authId && !NON_USER_AUTH_TYPES.has(event.authType) ? event.authId : null;

    const recipients = slotNotificationRecipients(before, after, authUid);
    if (recipients.length === 0) return;

    const slot = after || before;
    const slotEnd = (slot.endDateTime || slot.startDateTime)?.toDate?.();
    if (!slotEnd || slotEnd < new Date()) return; // termin je već prošao

    const actorName = await userDisplayName(slotActor(before, after, authUid));
    const slotTime = formatSlotTime(slot.startDateTime);

    try {
      await sendSlotNotifications({ orgId, slotId, recipients, actorName, slotTime });
    } catch (e) {
      console.error(`notifySlotChange failed for ${orgId}/${slotId}:`, e);
    }
  }
);

/** Ko je napravio promjenu: iz auth contexta, a za rezervu polja iz aplikacije. */
function slotActor(before, after, authUid) {
  if (authUid) return authUid;
  return after ? after.lastModifiedBy : before?.deletedBy;
}

/** Vraća [{ uid, type }] gdje je type created | updated | deleted. */
function slotNotificationRecipients(before, after, authUid) {
  const beforeIds = new Set(before?.employeeIds || []);
  const afterIds = new Set(after?.employeeIds || []);

  const recipients = [];

  if (!before && after) {
    afterIds.forEach((uid) => recipients.push({ uid, type: "created" }));
  } else if (before && !after) {
    beforeIds.forEach((uid) => recipients.push({ uid, type: "deleted" }));
  } else if (before && after && hasRelevantSlotChange(before, after)) {
    // Za zaposlenog koji je tek dodat na termin to je novi termin, a za
    // onoga koji je uklonjen termin je otkazan.
    afterIds.forEach((uid) =>
      recipients.push({ uid, type: beforeIds.has(uid) ? "updated" : "created" })
    );
    beforeIds.forEach((uid) => {
      if (!afterIds.has(uid)) recipients.push({ uid, type: "deleted" });
    });
  }

  const actor = slotActor(before, after, authUid);
  return recipients.filter((r) => r.uid && r.uid !== actor);
}

/** Username korisnika, a ako ga nema, ime i prezime. */
async function userDisplayName(uid) {
  if (!uid) return null;

  const user = (await db.collection("users").doc(uid).get()).data();
  const username = user?.username?.trim();
  if (username) return username;

  const fullName = `${user?.name || ""} ${user?.surname || ""}`.trim();
  return fullName || null;
}

function hasRelevantSlotChange(before, after) {
  const comparable = (value) => {
    if (value?.toMillis) return value.toMillis();
    if (Array.isArray(value)) return JSON.stringify([...value].sort());
    return JSON.stringify(value ?? null);
  };

  return SLOT_NOTIFY_FIELDS.some(
    (field) => comparable(before[field]) !== comparable(after[field])
  );
}

/** npr. "10.10.2026 u 16h" ili "10.10.2026 u 16:30h" u lokalnom vremenu salona. */
function formatSlotTime(timestamp) {
  const date = timestamp?.toDate?.();
  if (!date) return "";

  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", {
      timeZone: SLOT_TIME_ZONE,
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(date)
      .map((part) => [part.type, part.value])
  );

  const time = parts.minute === "00" ? parts.hour : `${parts.hour}:${parts.minute}`;
  return `${parts.day}.${parts.month}.${parts.year} u ${time}h`;
}

function slotNotificationBody(type, actorName, slotTime) {
  const action = actorName
    ? `${actorName} ${SLOT_NOTIFICATION_ACTIONS[type]}`
    : SLOT_NOTIFICATION_ACTIONS_WITHOUT_ACTOR[type];
  return `${action} za tebe na dan ${slotTime}`;
}

async function sendSlotNotifications({ orgId, slotId, recipients, actorName, slotTime }) {
  const typeByUid = new Map(recipients.map((r) => [r.uid, r.type]));
  const uids = [...typeByUid.keys()];

  const tokenDocs = [];
  for (let i = 0; i < uids.length; i += 30) {
    const snap = await db
      .collection(PUSH_TOKENS_COLLECTION)
      .where("uid", "in", uids.slice(i, i + 30))
      .get();
    tokenDocs.push(...snap.docs.filter((doc) => doc.data().orgId === orgId));
  }

  console.log(
    `notifySlotChange ${orgId}/${slotId}: primaoci ${JSON.stringify(recipients)}, tokena ${tokenDocs.length}`
  );
  if (tokenDocs.length === 0) return;

  const messages = tokenDocs.map((doc) => {
    const { token, uid } = doc.data();
    const type = typeByUid.get(uid);

    return {
      token,
      notification: {
        title: SLOT_NOTIFICATION_TITLES[type],
        body: slotNotificationBody(type, actorName, slotTime),
      },
      data: { type, slotId, orgId },
      android: { priority: "high", notification: { sound: "default" } },
      apns: { payload: { aps: { sound: "default" } } },
    };
  });

  const response = await admin.messaging().sendEach(messages);
  response.responses.forEach((result, index) => {
    const uid = tokenDocs[index].data().uid;
    if (result.success) {
      console.log(`notifySlotChange: poslano ${uid} (${result.messageId})`);
    } else {
      console.error(`notifySlotChange: slanje za ${uid} nije uspjelo: ${result.error?.code} ${result.error?.message}`);
    }
  });

  const invalidTokenRefs = response.responses
    .map((result, index) =>
      !result.success && INVALID_TOKEN_CODES.has(result.error?.code)
        ? tokenDocs[index].ref
        : null
    )
    .filter(Boolean);

  await Promise.all(invalidTokenRefs.map((ref) => ref.delete()));
}


// ---------------------------------------------------------------------------
// Termini: provjera preklapanja i upis u jednoj transakciji
// ---------------------------------------------------------------------------

const SLOT_OVERLAP_MESSAGE =
  "Termin se preklapa s drugim terminom. Molimo Vas izaberite drugi termin.";

function readMillis(value, field) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpsError("invalid-argument", `${field} je obavezan.`);
  }
  return admin.firestore.Timestamp.fromMillis(value);
}

function readStringList(value, field) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    throw new HttpsError("invalid-argument", `${field} mora biti lista.`);
  }
  return value;
}

function readOptionalString(value) {
  return typeof value === "string" ? value : null;
}

/**
 * Callable: saveSlot
 *
 * Aplikacija provjerava preklapanje pa upisuje termin, pa dva uređaja koja
 * u isto vrijeme zakažu isti termin oba prođu provjeru. Ovdje su provjera i
 * upis u istoj transakciji: druga transakcija vidi prvi termin i odbija se.
 *
 * request.data:
 *  {
 *    slotId: string,       // id generiše aplikacija, isti i za novi termin
 *    isNew: boolean,
 *    startDateTime: number, endDateTime: number,  // millis
 *    employeeIds: string[], serviceIds: string[],
 *    clientId?, clientName?, color?, title?
 *  }
 */
exports.saveSlot = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Moraš biti ulogovan.");
  }
  const uid = request.auth.uid;
  const data = request.data || {};

  const slotId = data.slotId;
  if (!slotId || typeof slotId !== "string" || slotId.includes("/")) {
    throw new HttpsError("invalid-argument", "slotId je obavezan.");
  }
  const start = readMillis(data.startDateTime, "startDateTime");
  const end = readMillis(data.endDateTime, "endDateTime");
  if (end.toMillis() <= start.toMillis()) {
    throw new HttpsError("invalid-argument", "Kraj termina mora biti poslije početka.");
  }
  const employeeIds = readStringList(data.employeeIds, "employeeIds");
  const serviceIds = readStringList(data.serviceIds ?? [], "serviceIds");

  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.data();
  if (!userSnap.exists || !user?.orgId || user?.isActive === false) {
    throw new HttpsError("permission-denied", "Nalog nije aktivan.");
  }

  const slots = db.collection("organizations").doc(user.orgId).collection("slots");
  const slotRef = slots.doc(slotId);

  const fields = {
    title: readOptionalString(data.title),
    color: readOptionalString(data.color),
    startDateTime: start,
    endDateTime: end,
    serviceIds,
    employeeIds,
    clientId: readOptionalString(data.clientId),
    clientName: readOptionalString(data.clientName),
    lastModifiedBy: uid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(slotRef);
    if (!data.isNew && !existing.exists) {
      // not-found aplikacija tumači kao funkciju koja nije deployovana.
      throw new HttpsError("failed-precondition", "Termin više ne postoji.");
    }

    for (const employeeId of employeeIds) {
      const overlapping = await transaction.get(
        slots
          .where("employeeIds", "array-contains", employeeId)
          .where("startDateTime", "<", end)
          .where("endDateTime", ">", start)
          .orderBy("startDateTime")
      );
      if (overlapping.docs.some((doc) => doc.id !== slotId)) {
        throw new HttpsError("already-exists", SLOT_OVERLAP_MESSAGE);
      }
    }

    if (existing.exists) {
      transaction.update(slotRef, fields);
    } else {
      transaction.set(slotRef, { ...fields, createdBy: uid });
    }
  });

  return { slotId };
});


// ---------------------------------------------------------------------------
// Klijenti: updatedAt za delta-sync i denormalizovano ime na terminima
// ---------------------------------------------------------------------------

/**
 * - Postavlja updatedAt kad ga izmjena nije postavila (starije verzije
 *   aplikacije), jer aplikacija sinhronizuje samo klijente sa novijim
 *   updatedAt-om.
 * - Kad se klijentu promijeni ime, prepisuje clientName na svim njegovim
 *   terminima. clientName nije u SLOT_NOTIFY_FIELDS, pa to ne šalje
 *   notifikacije.
 */
exports.onClientWritten = onDocumentWritten(
  "organizations/{orgId}/clients/{clientId}",
  async (event) => {
    const { orgId, clientId } = event.params;
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    if (!after) return;

    const updatedAtUnchanged =
      (before?.updatedAt?.toMillis?.() ?? null) === (after.updatedAt?.toMillis?.() ?? null);
    // Upis samog updatedAt-a ponovo okida ovu funkciju; tada je updatedAt
    // promijenjen, pa se ovdje ne upisuje ponovo.
    if (updatedAtUnchanged) {
      await event.data.after.ref.update({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (!before || before.name === after.name) return;

    const slotsSnap = await db
      .collection("organizations")
      .doc(orgId)
      .collection("slots")
      .where("clientId", "==", clientId)
      .get();

    const writer = db.bulkWriter();
    slotsSnap.docs.forEach((doc) => {
      if (doc.data().clientName !== after.name) {
        writer.update(doc.ref, { clientName: after.name || null });
      }
    });
    await writer.close();
  }
);
