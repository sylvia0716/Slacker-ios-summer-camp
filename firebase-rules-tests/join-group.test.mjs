import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteApp, initializeApp } from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInAnonymously,
} from "firebase/auth";
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from "firebase/functions";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from "firebase/firestore";

const projectId = "demo-group-bomb";
const groupID = "11111111-1111-4111-8111-111111111111";
const taskID = "22222222-2222-4222-8222-222222222222";
const attachmentID = "33333333-3333-4333-8333-333333333333";
const validCode = "JOIN24";
const inactiveCode = "OFF024";
const expiredCode = "OLD024";
let testEnv;
let clientSequence = 0;

async function seedData() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, `groups/${groupID}`), {
      name: "跨手機測試群組",
      deadline: Timestamp.fromMillis(Date.now() + 86_400_000),
      inviteCode: validCode,
    });
    await setDoc(doc(firestore, `groupInviteCodes/${validCode}`), {
      groupID,
      isActive: true,
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(firestore, `groupInviteCodes/${inactiveCode}`), {
      groupID,
      isActive: false,
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(firestore, `groupInviteCodes/${expiredCode}`), {
      groupID,
      isActive: true,
      expiresAt: Timestamp.fromMillis(Date.now() - 1_000),
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(firestore, `groups/${groupID}/tasks/${taskID}`), {
      title: "測試任務",
    });
  });
}

async function callableClient(authenticated = true) {
  const app = initializeApp(
    { apiKey: "demo-api-key", projectId, appId: `demo-${++clientSequence}` },
    `join-test-${clientSequence}`,
  );
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  const functions = getFunctions(app, "asia-east1");
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);

  let userID = null;
  if (authenticated) {
    const credential = await signInAnonymously(auth);
    userID = credential.user.uid;
  }

  return {
    userID,
    create: httpsCallable(functions, "createGroup"),
    join: httpsCallable(functions, "joinGroupByInviteCode"),
    list: httpsCallable(functions, "listMyGroups"),
    progress: httpsCallable(functions, "updateTaskProgress"),
    createTask: httpsCallable(functions, "createTask"),
    updateSubtask: httpsCallable(functions, "updateSubtask"),
    close: () => deleteApp(app),
  };
}

async function expectCallableFailure(promise, expectedCode) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, expectedCode);
    return true;
  });
}

// Unrelated task tests start with an approved membership. Approval itself is
// exercised against the callable transaction in join-approval.test.mjs.
async function seedMembership(client) {
  await testEnv.withSecurityRulesDisabled(ctx => setDoc(
    doc(ctx.firestore(), `groups/${groupID}/members/${client.userID}`),
    {userID: client.userID, role: 'member', displayName: 'Test member', joinedAt: Timestamp.now()},
  ));
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

beforeEach(async () => {
  // Background Firestore triggers may still hold a transaction from the prior test.
  // Retry only this emulator cleanup conflict; assertion failures are never retried.
  for (let attempt = 0; ; attempt++) {
    try {
      await testEnv.clearFirestore();
      break;
    } catch (error) {
      if (attempt >= 4 || !String(error).includes('Transaction lock timeout')) throw error;
      await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1)));
    }
  }
  await seedData();
});

after(async () => {
  await testEnv.cleanup();
});

describe("雲端任務共識驗收", () => {
  async function fixture(includeSecondReviewer = true) {
    const a = await callableClient(), b = await callableClient(), c = await callableClient();
    const reviewer = await callableClient();
    await seedMembership(a);
    await seedMembership(b);
    if (includeSecondReviewer) await seedMembership(reviewer);
    await testEnv.withSecurityRulesDisabled(async ctx => {
      await updateDoc(doc(ctx.firestore(), `groups/${groupID}/tasks/${taskID}`), {ownerMemberID: b.userID, subtasks: []});
      await setDoc(doc(ctx.firestore(), `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}`), {
        status: 'ready', createdAt: Timestamp.now(), uploaderID: b.userID,
      });
    });
    return {a,b,c,reviewer,close: () => Promise.all([a.close(), b.close(), c.close(), reviewer.close()])};
  }
  const confirm = {groupID, taskID, action:'confirm', attachmentID};
  test('全部其他成員確認才完成，負責人不得自我確認，重複確認不增加票數', async () => {
    const f = await fixture();
    try {
      assert.equal((await f.a.progress(confirm)).data.status, 'submitted');
      assert.equal((await f.a.progress(confirm)).data.status, 'submitted');
      await expectCallableFailure(f.b.progress(confirm), 'functions/permission-denied');
      assert.equal((await f.reviewer.progress(confirm)).data.status, 'completed');
      const task = await getDoc(doc(testEnv.authenticatedContext(f.a.userID).firestore(), `groups/${groupID}/tasks/${taskID}`));
      assert.deepEqual(new Set(task.data().confirmedMemberUIDs), new Set([f.a.userID,f.reviewer.userID]));
    } finally { await f.close(); }
  });
  test('雙人群組只需另一位成員確認，不等待負責人', async () => {
    const f = await fixture(false);
    try {
      assert.equal((await f.a.progress(confirm)).data.status, 'completed');
      await expectCallableFailure(f.b.progress(confirm), 'functions/permission-denied');
      const task = await getDoc(doc(testEnv.authenticatedContext(f.a.userID).firestore(), `groups/${groupID}/tasks/${taskID}`));
      assert.deepEqual(task.data().confirmedMemberUIDs, [f.a.userID]);
    } finally { await f.close(); }
  });
  test('拒絕未登入、非成員、偽造 UID 或自行指定完成狀態', async () => {
    const f = await fixture(), guest = await callableClient(false);
    try {
      await expectCallableFailure(guest.progress(confirm), 'functions/unauthenticated');
      await expectCallableFailure(f.c.progress(confirm), 'functions/permission-denied');
      await expectCallableFailure(f.a.progress({...confirm, userID:f.b.userID}), 'functions/invalid-argument');
      await expectCallableFailure(f.a.progress({...confirm, status:'completed'}), 'functions/invalid-argument');
    } finally { await f.close(); await guest.close(); }
  });
  test('只有負責人可更新子任務，未完成不得確認，重新修改後清空確認', async () => {
    const f=await fixture(), subtaskID='44444444-4444-4444-8444-444444444444';
    try {
      await testEnv.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), `groups/${groupID}/tasks/${taskID}`), {subtasks:[{id:subtaskID,title:'工作',weight:1,isComplete:false}]}));
      await expectCallableFailure(f.a.progress(confirm), 'functions/failed-precondition');
      const update={groupID,taskID,action:'setSubtask',subtaskID,isComplete:true};
      await expectCallableFailure(f.a.progress(update), 'functions/permission-denied');
      await f.b.progress(update);
      await f.a.progress(confirm); await f.reviewer.progress(confirm);
      assert.equal((await f.b.progress({...update,isComplete:false})).data.status, 'submitted');
      const task=await getDoc(doc(testEnv.authenticatedContext(f.b.userID).firestore(),`groups/${groupID}/tasks/${taskID}`));
      assert.deepEqual(task.data().confirmedMemberUIDs, []);
    } finally { await f.close(); }
  });
  test('新成果不能沿用舊確認，舊成果確認被拒絕', async () => {
    const f=await fixture();
    try {
      await f.a.progress(confirm); await f.reviewer.progress(confirm);
      const next='55555555-5555-4555-8555-555555555555';
      await testEnv.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(),`groups/${groupID}/tasks/${taskID}/attachments/${next}`),{status:'ready',createdAt:Timestamp.fromMillis(Date.now()+1000),uploaderID:f.b.userID}));
      await expectCallableFailure(f.a.progress(confirm),'functions/failed-precondition');
      assert.equal((await f.a.progress({...confirm,attachmentID:next})).data.status,'submitted');
      assert.equal((await f.reviewer.progress({...confirm,attachmentID:next})).data.status,'completed');
    } finally { await f.close(); }
  });
  test('既有成員查詢保留成員名稱', async () => {
    const a=await callableClient();
    try {
      await seedMembership(a);
      await a.join({inviteCode:validCode});
      const member=await getDoc(doc(testEnv.authenticatedContext(a.userID).firestore(),`groups/${groupID}/members/${a.userID}`));
      assert.ok(member.data().displayName.length>0);
    } finally { await a.close(); }
  });
});

describe("joinGroupByInviteCode Callable", () => {
  test("已登入使用者建立群組時，同步建立 leader、邀請碼與可讀取的群組", async () => {
    const client = await callableClient();
    try {
      const deadlineMillis = Date.now() + 86_400_000;
      const response = await client.create({
        name: " 新測試群組 ",
        deadlineMillis,
        displayName: "Peach",
      });
      const createdGroupID = response.data.group.groupID;
      const inviteCode = response.data.group.inviteCode;

      assert.match(createdGroupID, /^[0-9a-f-]{36}$/);
      assert.match(inviteCode, /^[A-Z0-9]{6}$/);
      assert.equal(response.data.group.name, "新測試群組");

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const firestore = context.firestore();
        const group = await getDoc(doc(firestore, `groups/${createdGroupID}`));
        const member = await getDoc(doc(
          firestore,
          `groups/${createdGroupID}/members/${client.userID}`,
        ));
        const invite = await getDoc(doc(firestore, `groupInviteCodes/${inviteCode}`));
        assert.equal(group.data().name, "新測試群組");
        assert.equal(member.data().role, "leader");
        assert.equal(member.data().displayName, "Peach");
        assert.equal(invite.data().groupID, createdGroupID);
      });

      const groups = await client.list({});
      assert.ok(groups.data.groups.some(group => group.groupID === createdGroupID));

      const memberFirestore = testEnv.authenticatedContext(client.userID).firestore();
      await assertSucceeds(getDocs(collection(
        memberFirestore,
        `groups/${createdGroupID}/messages`,
      )));
      await assertSucceeds(setDoc(doc(
        memberFirestore,
        `groups/${createdGroupID}/presence/${client.userID}`,
      ), {
        userID: client.userID,
        displayName: "Peach",
        isOnline: true,
        lastSeenAt: serverTimestamp(),
      }));
    } finally {
      await client.close();
    }
  });

  test("建立群組拒絕未登入、無效欄位、空白名稱與過期期限", async () => {
    const guest = await callableClient(false);
    const client = await callableClient();
    const valid = {
      name: "測試群組",
      deadlineMillis: Date.now() + 86_400_000,
      displayName: "Peach",
    };
    try {
      await expectCallableFailure(guest.create(valid), "functions/unauthenticated");
      await expectCallableFailure(client.create({ ...valid, role: "leader" }), "functions/invalid-argument");
      await expectCallableFailure(client.create({ ...valid, name: "   " }), "functions/invalid-argument");
      await expectCallableFailure(
        client.create({ ...valid, deadlineMillis: Date.now() - 1_000 }),
        "functions/invalid-argument",
      );
    } finally {
      await guest.close();
      await client.close();
    }
  });

  test("舊版加入接口不能繞過組長審核", async () => {
    const client = await callableClient();
    try {
      await expectCallableFailure(client.join({ inviteCode: "  join24  " }), "functions/failed-precondition");

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const snapshot = await getDoc(doc(
          context.firestore(),
          `groups/${groupID}/members/${client.userID}`,
        ));
        assert.equal(snapshot.exists(), false);
      });
    } finally {
      await client.close();
    }
  });

  test("重複加入安全且不會建立重複 member", async () => {
    const client = await callableClient();
    try {
      await seedMembership(client);
      const second = await client.join({ inviteCode: validCode });
      assert.equal(second.data.alreadyMember, true);

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const members = await getDocs(collection(
          context.firestore(),
          `groups/${groupID}/members`,
        ));
        assert.equal(members.size, 1);
      });
    } finally {
      await client.close();
    }
  });

  test("加入後可重新讀取群組，並可依 Rules 讀取附件", async () => {
    const client = await callableClient();
    try {
      await seedMembership(client);
      const groups = await client.list({});
      assert.equal(groups.data.groups.length, 1);
      assert.equal(groups.data.groups[0].groupID, groupID);

      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(
          context.firestore(),
          `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}`,
        ), {
          id: attachmentID,
          taskID,
          groupID,
          uploaderID: client.userID,
          title: "成果",
          detail: "",
          kind: "pdf",
          originalFilename: "report.pdf",
          storagePath: `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}/report-33333333.pdf`,
          externalURL: null,
          contentType: "application/pdf",
          byteSize: 100,
          status: "ready",
          createdAt: Timestamp.now(),
        });
      });
      const attachment = doc(
        testEnv.authenticatedContext(client.userID).firestore(),
        `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}`,
      );
      await assertSucceeds(getDoc(attachment));
    } finally {
      await client.close();
    }
  });

  test("未登入、無效、停用與過期邀請碼均被拒絕", async () => {
    const guest = await callableClient(false);
    const member = await callableClient();
    try {
      await expectCallableFailure(
        guest.join({ inviteCode: validCode }),
        "functions/unauthenticated",
      );
      for (const inviteCode of ["12345", "1234567", "ABCD2345", "AB-123"]) {
        await expectCallableFailure(
          member.join({ inviteCode }),
          "functions/invalid-argument",
        );
      }
      await expectCallableFailure(
        member.join({ inviteCode: "NONE24" }),
        "functions/not-found",
      );
      await expectCallableFailure(
        member.join({ inviteCode: inactiveCode }),
        "functions/failed-precondition",
      );
      await expectCallableFailure(
        member.join({ inviteCode: expiredCode }),
        "functions/failed-precondition",
      );
    } finally {
      await guest.close();
      await member.close();
    }
  });

  test("Client 不能指定 userID 或 leader role", async () => {
    const client = await callableClient();
    try {
      await expectCallableFailure(
        client.join({ inviteCode: validCode, userID: "victim" }),
        "functions/invalid-argument",
      );
      await expectCallableFailure(
        client.join({ inviteCode: validCode, role: "leader" }),
        "functions/invalid-argument",
      );
      await expectCallableFailure(
        client.join({ inviteCode: validCode, leader: true }),
        "functions/invalid-argument",
      );
      await expectCallableFailure(
        client.join({ inviteCode: validCode, groupID }),
        "functions/invalid-argument",
      );
    } finally {
      await client.close();
    }
  });

  test("到期日格式錯誤或群組不存在時拒絕加入", async () => {
    const client = await callableClient();
    try {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(doc(context.firestore(), `groupInviteCodes/${validCode}`), {
          expiresAt: "not-a-timestamp",
        });
      });
      await expectCallableFailure(client.join({ inviteCode: validCode }), "functions/failed-precondition");
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), `groupInviteCodes/${validCode}`), {
          groupID: "44444444-4444-4444-8444-444444444444",
          isActive: true,
          createdAt: Timestamp.now(),
        });
      });
      await expectCallableFailure(client.join({ inviteCode: validCode }), "functions/not-found");
    } finally {
      await client.close();
    }
  });

  test("同時查詢既有成員不重複建立，既有 leader 與 joinedAt 不被覆寫", async () => {
    const client = await callableClient();
    try {
      await seedMembership(client);
      const responses = await Promise.all([
        client.join({ inviteCode: validCode }),
        client.join({ inviteCode: validCode }),
      ]);
      assert.equal(responses.filter(response => response.data.alreadyMember === true).length, 2);
      const joinedAt = Timestamp.fromMillis(1_700_000_000_000);
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const firestore = context.firestore();
        assert.equal((await getDocs(collection(firestore, `groups/${groupID}/members`))).size, 1);
        await updateDoc(doc(firestore, `groups/${groupID}/members/${client.userID}`), {
          role: "leader", joinedAt,
        });
      });
      assert.equal((await client.join({ inviteCode: validCode })).data.alreadyMember, true);
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const member = await getDoc(doc(context.firestore(), `groups/${groupID}/members/${client.userID}`));
        assert.equal(member.data().role, "leader");
        assert.equal(member.data().joinedAt.toMillis(), joinedAt.toMillis());
      });
    } finally {
      await client.close();
    }
  });

  test("非成員不可讀附件，Client 不可直接建立或升級 member", async () => {
    const client = await callableClient();
    try {
      const firestore = testEnv.authenticatedContext(client.userID).firestore();
      await assertFails(getDoc(doc(
        firestore,
        `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}`,
      )));
      await assertFails(setDoc(doc(
        firestore,
        `groups/${groupID}/members/${client.userID}`,
      ), { userID: client.userID, role: "leader", joinedAt: Timestamp.now() }));

      await seedMembership(client);
      await assertFails(updateDoc(doc(
        firestore,
        `groups/${groupID}/members/${client.userID}`,
      ), { role: "leader" }));
    } finally {
      await client.close();
    }
  });

  test("listMyGroups 拒絕未登入與 Client 指定 userID、role 或 groupID", async () => {
    const guest = await callableClient(false);
    const client = await callableClient();
    try {
      await expectCallableFailure(guest.list({}), "functions/unauthenticated");
      for (const data of [{ userID: "victim" }, { role: "leader" }, { groupID }]) {
        await expectCallableFailure(client.list(data), "functions/invalid-argument");
      }
    } finally {
      await guest.close();
      await client.close();
    }
  });

  test("listMyGroups 只列出呼叫者確實擁有 member 文件的群組", async () => {
    const first = await callableClient();
    const second = await callableClient();
    try {
      assert.deepEqual((await first.list({})).data.groups, []);
      await seedMembership(first);
      assert.deepEqual((await first.list({})).data.groups.map(group => group.groupID), [groupID]);
      assert.deepEqual((await second.list({})).data.groups, []);
    } finally {
      await first.close();
      await second.close();
    }
  });

  test("listMyGroups 忽略 UID 欄位相符但文件 ID 或群組層級錯誤的資料", async () => {
    const client = await callableClient();
    try {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const firestore = context.firestore();
        await setDoc(doc(firestore, `groups/${groupID}/members/not-the-caller`), {
          userID: client.userID, role: "member",
        });
        await setDoc(doc(firestore, "privateSpaces/not-a-group"), { name: "不可外洩" });
        await setDoc(doc(firestore, `privateSpaces/not-a-group/members/${client.userID}`), {
          userID: client.userID, role: "member",
        });
        await setDoc(doc(firestore, "workspaces/one/groups/nested-group"), { name: "非正式群組路徑" });
        await setDoc(doc(firestore, `workspaces/one/groups/nested-group/members/${client.userID}`), {
          userID: client.userID, role: "member",
        });
        await setDoc(doc(firestore, `groups/deleted-group/members/${client.userID}`), {
          userID: client.userID, role: "member",
        });
      });
      assert.deepEqual((await client.list({})).data.groups, []);
      await seedMembership(client);
      assert.deepEqual((await client.list({})).data.groups.map(group => group.groupID), [groupID]);
    } finally {
      await client.close();
    }
  });

  test("群組成員發布任務後，負責人可以同步子任務進度", async () => {
    const client = await callableClient();
    const newTaskID = "55555555-5555-4555-8555-555555555555";
    const subtaskID = "66666666-6666-4666-8666-666666666666";
    try {
      await seedMembership(client);
      await client.createTask({
        groupID,
        taskID: newTaskID,
        title: " 製作簡報 ",
        detail: "完成期末簡報",
        assigneeUserID: client.userID,
        subtasks: [{ id: subtaskID, title: "整理大綱" }],
        deadlineMillis: Date.now() + 3_600_000,
      });

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const snapshot = await getDoc(doc(context.firestore(), `groups/${groupID}/tasks/${newTaskID}`));
        assert.equal(snapshot.data().title, "製作簡報");
        assert.equal(snapshot.data().ownerMemberID, client.userID);
        assert.equal(snapshot.data().createdByMemberID, client.userID);
        assert.equal(snapshot.data().status, "inProgress");
        assert.equal(snapshot.data().subtasks[0].isComplete, false);
        assert.equal(snapshot.data().subtasks[0].weight, 100);
        assert.ok(snapshot.data().createdAt instanceof Timestamp);
      });

      const response = await client.updateSubtask({
        groupID,
        taskID: newTaskID,
        subtaskID,
        isComplete: true,
      });
      assert.equal(response.data.status, "completed");

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const snapshot = await getDoc(doc(context.firestore(), `groups/${groupID}/tasks/${newTaskID}`));
        assert.equal(snapshot.data().status, "completed");
        assert.equal(snapshot.data().subtasks[0].isComplete, true);
      });
    } finally {
      await client.close();
    }
  });

  test("非成員不能發布任務，非負責人不能修改子任務", async () => {
    const owner = await callableClient();
    const other = await callableClient();
    const outsider = await callableClient();
    const newTaskID = "77777777-7777-4777-8777-777777777777";
    const subtaskID = "88888888-8888-4888-8888-888888888888";
    const taskPayload = {
      groupID,
      taskID: newTaskID,
      title: "安全測試",
      detail: "",
      assigneeUserID: owner.userID,
      subtasks: [{ id: subtaskID, title: "只能由負責人完成" }],
      deadlineMillis: Date.now() + 3_600_000,
    };
    try {
      await seedMembership(owner);
      await seedMembership(other);
      await expectCallableFailure(outsider.createTask(taskPayload), "functions/permission-denied");
      await owner.createTask(taskPayload);
      await expectCallableFailure(other.updateSubtask({
        groupID,
        taskID: newTaskID,
        subtaskID,
        isComplete: true,
      }), "functions/permission-denied");
    } finally {
      await owner.close();
      await other.close();
      await outsider.close();
    }
  });
});
