import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, where, orderBy, limit, serverTimestamp, setDoc, Timestamp, updateDoc,
} from "firebase/firestore";

// Always local: FIRESTORE_RULES_FILE selects a Rules snapshot, never a production project.
const projectId = "demo-group-bomb";
const groupID = "chat-group";
const memberID = "chat-member";
const teammateID = "chat-teammate";
const leaderID = "chat-leader";
const outsiderID = "chat-outsider";
let testEnv;

function db(uid) {
  return uid ? testEnv.authenticatedContext(uid).firestore() : testEnv.unauthenticatedContext().firestore();
}

function messageRef(uid, id = "message-one") {
  return doc(db(uid), `groups/${groupID}/messages/${id}`);
}

function presenceRef(uid, target = uid) {
  return doc(db(uid), `groups/${groupID}/presence/${target}`);
}

function memberRef(uid, target = uid) {
  return doc(db(uid), `groups/${groupID}/members/${target}`);
}

function message(overrides = {}) {
  return {
    id: "message-one", senderID: memberID, senderName: "測試組員",
    text: "今天已完成簡報", kind: "message", createdAt: serverTimestamp(), ...overrides,
  };
}

function presence(uid = memberID, overrides = {}) {
  return {
    userID: uid, displayName: "測試組員", isOnline: true, lastSeenAt: serverTimestamp(), ...overrides,
  };
}

async function seedMessage() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `groups/${groupID}/messages/message-one`), {
      ...message(), createdAt: Timestamp.fromMillis(1000),
    });
  });
}

async function seedPresence(uid = memberID) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `groups/${groupID}/presence/${uid}`), {
      ...presence(uid), lastSeenAt: Timestamp.fromMillis(1000),
    });
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(
        process.env.FIRESTORE_RULES_FILE ?? new URL("../firestore.rules", import.meta.url), "utf8",
      ),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, `groups/${groupID}`), { name: "聊天室測試群組" });
    for (const uid of [memberID, teammateID, leaderID]) {
      await setDoc(doc(firestore, `groups/${groupID}/members/${uid}`), {
        userID: uid, displayName: "測試組員", role: uid === leaderID ? "leader" : "member",
        joinedAt: Timestamp.fromMillis(1000),
      });
    }
  });
});

after(async () => { await testEnv.cleanup(); });

describe("戳戳接收權限", () => {
  test("只有仍在群組的接收者能讀取；用戶端不能偽造或修改事件", async () => {
    const path = `groups/${groupID}/pokes/poke-one`;
    const event = { senderID: teammateID, recipientID: memberID, style: "輕敲", pokeCount: 1,
      groupName: "測試群組", createdAt: Timestamp.fromMillis(1000) };
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), path), event);
    });
    await assertSucceeds(getDoc(doc(db(memberID), path)));
    await assertSucceeds(getDocs(query(collection(db(memberID), `groups/${groupID}/pokes`),
      where("recipientID", "==", memberID), orderBy("createdAt"))));
    await assertSucceeds(getDocs(query(collection(db(memberID), `groups/${groupID}/pokes`),
      where("recipientID", "==", memberID), orderBy("createdAt", "desc"), limit(1))));
    for (const uid of [teammateID, leaderID, outsiderID, null]) {
      await assertFails(getDoc(doc(db(uid), path)));
    }
    await assertFails(getDocs(collection(db(memberID), `groups/${groupID}/pokes`)));
    await assertFails(setDoc(doc(db(memberID), `${path}-forged`), event));
    await assertFails(updateDoc(doc(db(memberID), path), { pokeCount: 99 }));
    await assertFails(deleteDoc(doc(db(memberID), path)));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await deleteDoc(doc(context.firestore(), `groups/${groupID}/members/${memberID}`));
    });
    await assertFails(getDoc(doc(db(memberID), path)));
  });
});

describe("Group Bomb 聊天室相容性與存取回歸", () => {
  test("成員可傳送訊息，其他組員可讀取與列出訊息", async () => {
    await assertSucceeds(setDoc(messageRef(memberID), message()));
    const received = await assertSucceeds(getDoc(messageRef(teammateID)));
    assert.equal(received.data().senderID, memberID);
    assert.equal(received.data().text, "今天已完成簡報");
    await assertSucceeds(getDocs(collection(db(teammateID), `groups/${groupID}/messages`)));
  });

  test("保留組員傳送 botReply 與 botAnalysis 的既有格式", async () => {
    await assertSucceeds(setDoc(messageRef(memberID, "reply-one"), message({
      id: "reply-one", kind: "botReply",
    })));
    await assertSucceeds(setDoc(messageRef(memberID, "analysis-one"), message({
      id: "analysis-one", kind: "botAnalysis", analysisScore: 81,
      analysisStrength: "分工清楚", analysisSuggestion: "確認剩餘任務",
    })));
    await assertSucceeds(getDoc(messageRef(teammateID, "analysis-one")));
  });

  test("未登入不可讀取、傳送、修改或刪除訊息", async () => {
    await seedMessage();
    await assertFails(getDoc(messageRef()));
    await assertFails(setDoc(messageRef(null, "new-one"), message({ id: "new-one" })));
    await assertFails(updateDoc(messageRef(), { text: "偽造" }));
    await assertFails(deleteDoc(messageRef()));
  });

  test("非成員不可讀取、列出或傳送群組訊息", async () => {
    await seedMessage();
    await assertFails(getDoc(messageRef(outsiderID)));
    await assertFails(getDocs(collection(db(outsiderID), `groups/${groupID}/messages`)));
    await assertFails(setDoc(messageRef(outsiderID, "new-one"), message({
      id: "new-one", senderID: outsiderID,
    })));
  });

  test("其他群組的 member 或 leader 不會獲得本群組聊天室權限", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `groups/other-group/members/${outsiderID}`), {
        userID: outsiderID, role: "leader",
      });
    });
    await seedMessage();
    await assertFails(getDoc(messageRef(outsiderID)));
    await assertFails(setDoc(messageRef(outsiderID, "new-one"), message({
      id: "new-one", senderID: outsiderID,
    })));
  });

  test("成員不能偽造 senderID 或訊息文件 ID", async () => {
    await assertFails(setDoc(messageRef(memberID), message({ senderID: teammateID })));
    await assertFails(setDoc(messageRef(memberID), message({ id: "wrong-id" })));
  });

  test("訊息欄位、文字長度、kind 與 server timestamp 限制保留", async () => {
    for (const changes of [
      { text: "" }, { text: "x".repeat(4001) }, { senderName: "" },
      { senderName: "x".repeat(61) }, { kind: "admin" }, { unexpected: true },
      { createdAt: Timestamp.fromMillis(0) },
    ]) {
      await assertFails(setDoc(messageRef(memberID), message(changes)));
    }
    const missing = message();
    delete missing.senderName;
    await assertFails(setDoc(messageRef(memberID), missing));
  });

  test("botAnalysis 分數與必填欄位驗證保留", async () => {
    const analysis = {
      kind: "botAnalysis", analysisScore: 81, analysisStrength: "完成核心工作", analysisSuggestion: "確認成果",
    };
    for (const changes of [
      { analysisScore: -1 }, { analysisScore: 101 }, { analysisScore: 81.5 },
      { analysisStrength: "" }, { analysisSuggestion: "x".repeat(4001) },
    ]) {
      await assertFails(setDoc(messageRef(memberID), message({ ...analysis, ...changes })));
    }
    await assertFails(setDoc(messageRef(memberID), message({ kind: "botAnalysis" })));
    await assertFails(setDoc(messageRef(memberID), message({ analysisScore: 81 })));
  });

  test("已送出的訊息不可由 sender、其他 member 或 leader 修改與刪除", async () => {
    await seedMessage();
    for (const actor of [memberID, teammateID, leaderID]) {
      await assertFails(updateDoc(messageRef(actor), { text: "修改後" }));
      await assertFails(deleteDoc(messageRef(actor)));
    }
  });

  test("成員可建立與更新自己的 presence，其他成員可讀取與列出", async () => {
    await assertSucceeds(setDoc(presenceRef(memberID), presence()));
    await assertSucceeds(updateDoc(presenceRef(memberID), {
      isOnline: false, lastSeenAt: serverTimestamp(),
    }));
    const received = await assertSucceeds(getDoc(presenceRef(teammateID, memberID)));
    assert.equal(received.data().isOnline, false);
    await assertSucceeds(getDocs(collection(db(teammateID), `groups/${groupID}/presence`)));
  });

  test("成員可刪除自己的 presence，不可刪除其他人的 presence", async () => {
    await seedPresence();
    await assertFails(deleteDoc(presenceRef(teammateID, memberID)));
    await assertFails(deleteDoc(presenceRef(leaderID, memberID)));
    await assertSucceeds(deleteDoc(presenceRef(memberID)));
  });

  test("離開群組後仍可清理自己的舊 presence，但不能重建或更新", async () => {
    await seedPresence();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await deleteDoc(doc(context.firestore(), `groups/${groupID}/members/${memberID}`));
    });
    await assertFails(updateDoc(presenceRef(memberID), { isOnline: true, lastSeenAt: serverTimestamp() }));
    await assertFails(getDoc(presenceRef(memberID)));
    await assertSucceeds(deleteDoc(presenceRef(memberID)));
    await assertFails(setDoc(presenceRef(memberID), presence()));
  });

  test("未登入不可讀取、建立、更新或刪除 presence", async () => {
    await seedPresence();
    await assertFails(getDoc(presenceRef(null, memberID)));
    await assertFails(setDoc(presenceRef(null, "new-user"), presence("new-user")));
    await assertFails(updateDoc(presenceRef(null, memberID), { isOnline: false, lastSeenAt: serverTimestamp() }));
    await assertFails(deleteDoc(presenceRef(null, memberID)));
  });

  test("非成員不可讀取或偽造自己與別人的 presence", async () => {
    await seedPresence();
    await assertFails(getDoc(presenceRef(outsiderID, memberID)));
    await assertFails(getDocs(collection(db(outsiderID), `groups/${groupID}/presence`)));
    await assertFails(setDoc(presenceRef(outsiderID), presence(outsiderID)));
    await assertFails(updateDoc(presenceRef(outsiderID, memberID), { isOnline: false, lastSeenAt: serverTimestamp() }));
    await assertFails(deleteDoc(presenceRef(outsiderID, memberID)));
  });

  test("成員不可替其他 UID 建立 presence 或偽造 userID 欄位", async () => {
    await assertFails(setDoc(presenceRef(memberID, teammateID), presence(teammateID)));
    await assertFails(setDoc(presenceRef(memberID), presence(teammateID)));
  });

  test("presence schema、名稱長度與 server timestamp 驗證保留", async () => {
    for (const changes of [
      { displayName: "" }, { displayName: "x".repeat(61) }, { isOnline: "true" },
      { lastSeenAt: Timestamp.fromMillis(0) }, { unexpected: true },
    ]) {
      await assertFails(setDoc(presenceRef(memberID), presence(memberID, changes)));
    }
    const missing = presence();
    delete missing.isOnline;
    await assertFails(setDoc(presenceRef(memberID), missing));
  });

  test("保留讀取自己 member 文件及只更新自己 displayName 的權限", async () => {
    await assertSucceeds(getDoc(memberRef(memberID)));
    await assertSucceeds(getDoc(memberRef(teammateID, memberID)));
    // Existing chat can check for absent membership before presenting the join flow.
    assert.equal((await assertSucceeds(getDoc(memberRef(outsiderID)))).exists(), false);
    await assertFails(getDoc(memberRef(outsiderID, memberID)));
    await assertSucceeds(updateDoc(memberRef(memberID), { displayName: "新顯示名稱" }));
    await assertFails(updateDoc(memberRef(teammateID, memberID), { displayName: "偽造姓名" }));
    await assertFails(updateDoc(memberRef(memberID), { displayName: "" }));
    await assertFails(updateDoc(memberRef(memberID), { displayName: "x".repeat(61) }));
    await assertFails(updateDoc(memberRef(memberID), { displayName: "新名字", role: "leader" }));
  });

  test("成員只能透過 callable 退出，不能直接刪除成員或群組", async () => {
    await assertFails(deleteDoc(memberRef(teammateID, memberID)));
    await assertFails(deleteDoc(memberRef(leaderID, memberID)));
    await assertFails(deleteDoc(memberRef(null, memberID)));
    await assertFails(deleteDoc(memberRef(memberID)));
    for (const actor of [memberID, leaderID, outsiderID]) {
      await assertFails(deleteDoc(doc(db(actor), `groups/${groupID}`)));
    }
  });
});
