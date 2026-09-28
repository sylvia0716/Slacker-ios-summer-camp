import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from "firebase/firestore";

const projectId = "demo-group-bomb";
const groupID = "group-alpha";
const taskID = "task-one";
const attachmentID = "attachment-one";
const uploaderID = "member-uploader";
const teammateID = "member-teammate";
const leaderID = "member-leader";
const outsiderID = "outsider";
const attachmentPath =
  `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}`;
const safeStoragePath =
  `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}/report-a1b2c3d4.pdf`;

let testEnv;

function firestoreFor(userID) {
  return userID
    ? testEnv.authenticatedContext(userID).firestore()
    : testEnv.unauthenticatedContext().firestore();
}

function attachmentRef(userID, path = attachmentPath) {
  return doc(firestoreFor(userID), path);
}

function validFile(overrides = {}) {
  return {
    id: attachmentID,
    taskID,
    groupID,
    uploaderID,
    title: "期末報告",
    detail: "PDF 完成版",
    kind: "pdf",
    originalFilename: "期末報告.pdf",
    storagePath: safeStoragePath,
    externalURL: null,
    contentType: "application/pdf",
    byteSize: 1024,
    status: "ready",
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function validLink(overrides = {}) {
  return validFile({
    kind: "externalLink",
    originalFilename: null,
    storagePath: null,
    externalURL: "https://example.org/result",
    contentType: null,
    byteSize: null,
    ...overrides,
  });
}

async function seedBaseData() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, `groups/${groupID}`), { name: "測試群組" });
    await setDoc(doc(firestore, `groups/${groupID}/members/${uploaderID}`), {
      role: "member",
    });
    await setDoc(doc(firestore, `groups/${groupID}/members/${teammateID}`), {
      role: "member",
    });
    await setDoc(doc(firestore, `groups/${groupID}/members/${leaderID}`), {
      role: "leader",
    });
    await setDoc(doc(firestore, `groups/${groupID}/tasks/${taskID}`), {
      title: "測試任務",
    });
  });
}

async function seedAttachment(data = validFile()) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), attachmentPath), {
      ...data,
      createdAt: Timestamp.fromMillis(1_000),
    });
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      // Allows auditing a read-only deployed Rules snapshot in the local demo emulator.
      rules: readFileSync(
        process.env.FIRESTORE_RULES_FILE ?? new URL("../firestore.rules", import.meta.url),
        "utf8",
      ),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedBaseData();
});

after(async () => {
  await testEnv.cleanup();
});

describe("Group Bomb Firestore Security Rules", () => {
  test("未登入使用者不可讀取或建立附件", async () => {
    await seedAttachment();
    await assertFails(getDoc(attachmentRef()));
    await assertFails(setDoc(attachmentRef(), validFile()));
  });

  test("群組成員可以讀取，非成員不可讀取", async () => {
    await seedAttachment();
    await assertSucceeds(getDoc(attachmentRef(teammateID)));
    await assertFails(getDoc(attachmentRef(outsiderID)));
  });

  test("群組成員可以查詢附件清單，非成員不可查詢", async () => {
    await seedAttachment();
    const collectionPath =
      `groups/${groupID}/tasks/${taskID}/attachments`;
    await assertSucceeds(
      getDocs(collection(firestoreFor(teammateID), collectionPath)),
    );
    await assertFails(
      getDocs(collection(firestoreFor(outsiderID), collectionPath)),
    );
  });

  test("群組成員可以建立自己的合法檔案附件", async () => {
    await assertSucceeds(setDoc(attachmentRef(uploaderID), validFile()));
  });

  test("群組成員可以建立合法 HTTPS 連結附件", async () => {
    await assertSucceeds(setDoc(attachmentRef(uploaderID), validLink()));
  });

  test("HTTPS 附件接受小寫 UUID，拒絕舊版大寫 UUID", async () => {
    const upperID = "ABCDEF01-2345-4678-9ABC-DEF012345678";
    const lowerID = upperID.toLowerCase();
    const pathFor = (id) => `groups/${groupID}/tasks/${taskID}/attachments/${id}`;
    await assertFails(setDoc(attachmentRef(uploaderID, pathFor(upperID)), validLink({ id: upperID })));
    await assertSucceeds(setDoc(attachmentRef(uploaderID, pathFor(lowerID)), validLink({ id: lowerID })));
  });

  test("非成員或冒用其他 uploaderID 均不可建立附件", async () => {
    await assertFails(
      setDoc(attachmentRef(outsiderID), validFile({ uploaderID: outsiderID })),
    );
    await assertFails(
      setDoc(attachmentRef(uploaderID), validFile({ uploaderID: teammateID })),
    );
  });

  test("不存在的 taskID 不可建立附件", async () => {
    const missingTaskID = "missing-task";
    const path =
      `groups/${groupID}/tasks/${missingTaskID}/attachments/${attachmentID}`;
    const data = validFile({
      taskID: missingTaskID,
      storagePath:
        `groups/${groupID}/tasks/${missingTaskID}/attachments/${attachmentID}/report-a1b2c3d4.pdf`,
    });
    await assertFails(setDoc(attachmentRef(uploaderID, path), data));
  });

  test("偽造 createdAt 或非 ready 初始狀態不可建立", async () => {
    await assertFails(
      setDoc(
        attachmentRef(uploaderID),
        validFile({ createdAt: Timestamp.fromMillis(0) }),
      ),
    );
    await assertFails(
      setDoc(attachmentRef(uploaderID), validFile({ status: "pending" })),
    );
  });

  test("零位元、超過 20 MB 或不支援 MIME 不可建立", async () => {
    await assertFails(
      setDoc(attachmentRef(uploaderID), validFile({ byteSize: 0 })),
    );
    await assertFails(
      setDoc(
        attachmentRef(uploaderID),
        validFile({ byteSize: 20 * 1024 * 1024 + 1 }),
      ),
    );
    await assertFails(
      setDoc(
        attachmentRef(uploaderID),
        validFile({ contentType: "application/octet-stream" }),
      ),
    );
  });

  test("非 HTTPS URL、錯誤副檔名或不安全路徑不可建立", async () => {
    await assertFails(
      setDoc(
        attachmentRef(uploaderID),
        validLink({ externalURL: "http://example.org/result" }),
      ),
    );
    await assertFails(
      setDoc(
        attachmentRef(uploaderID),
        validFile({ storagePath: safeStoragePath.replace(".pdf", ".jpg") }),
      ),
    );
    await assertFails(
      setDoc(
        attachmentRef(uploaderID),
        validFile({
          storagePath:
            `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}/我的 報告.pdf`,
        }),
      ),
    );
  });

  test("標題、說明、原始檔名與 URL 長度均有限制", async () => {
    await assertFails(
      setDoc(attachmentRef(uploaderID), validFile({ title: "x".repeat(101) })),
    );
    await assertFails(
      setDoc(attachmentRef(uploaderID), validFile({ detail: "x".repeat(1001) })),
    );
    await assertFails(
      setDoc(
        attachmentRef(uploaderID),
        validFile({ originalFilename: `${"x".repeat(252)}.pdf` }),
      ),
    );
    await assertFails(
      setDoc(
        attachmentRef(uploaderID),
        validLink({ externalURL: `https://example.org/${"x".repeat(2030)}` }),
      ),
    );
  });

  test("原上傳者只能更新 title、detail 與 status", async () => {
    await seedAttachment();
    await assertSucceeds(
      updateDoc(attachmentRef(uploaderID), {
        title: "新版標題",
        detail: "新版說明",
        status: "failed",
      }),
    );
    await assertFails(
      updateDoc(attachmentRef(uploaderID), {
        storagePath:
          `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}/other-a1b2c3d4.pdf`,
      }),
    );
    await assertFails(
      updateDoc(attachmentRef(uploaderID), { uploaderID: teammateID }),
    );
    await assertFails(
      updateDoc(attachmentRef(teammateID), { title: "冒用更新" }),
    );
  });

  test("原上傳者可刪除，一般成員不可刪除別人的附件", async () => {
    await seedAttachment();
    await assertFails(deleteDoc(attachmentRef(teammateID)));
    await assertSucceeds(deleteDoc(attachmentRef(uploaderID)));
  });

  test("leader 可以刪除其他成員的附件", async () => {
    await seedAttachment();
    await assertSucceeds(deleteDoc(attachmentRef(leaderID)));
  });

  test("一般使用者不能建立或修改成員與角色", async () => {
    await assertFails(
      setDoc(
        doc(firestoreFor(uploaderID), `groups/${groupID}/members/new-member`),
        { role: "member" },
      ),
    );
    await assertFails(
      updateDoc(
        doc(firestoreFor(uploaderID), `groups/${groupID}/members/${uploaderID}`),
        { role: "leader" },
      ),
    );
  });

  test("非成員不可用完整合法資料替自己建立 member 繞過邀請碼", async () => {
    await assertFails(
      setDoc(
        doc(firestoreFor(outsiderID), `groups/${groupID}/members/${outsiderID}`),
        {
          userID: outsiderID,
          displayName: "測試非成員",
          role: "member",
          joinedAt: serverTimestamp(),
        },
      ),
    );
  });

  test("未登入與非成員不可讀取群組或任務，成員可以讀取", async () => {
    for (const path of [`groups/${groupID}`, `groups/${groupID}/tasks/${taskID}`]) {
      await assertSucceeds(getDoc(doc(firestoreFor(teammateID), path)));
      await assertFails(getDoc(doc(firestoreFor(), path)));
      await assertFails(getDoc(doc(firestoreFor(outsiderID), path)));
    }
    await assertFails(getDocs(collection(firestoreFor(outsiderID), `groups/${groupID}/tasks`)));
  });

  test("任何 Client 都不能替別人建立 member，包含群組 leader", async () => {
    for (const actor of [null, outsiderID, uploaderID, leaderID]) {
      await assertFails(setDoc(
        doc(firestoreFor(actor), `groups/${groupID}/members/new-member`),
        { userID: "new-member", displayName: "新成員", role: "member", joinedAt: serverTimestamp() },
      ));
    }
  });

  test("Client 不可自行建立 leader，或在不存在的群組建立 member", async () => {
    for (const role of ["leader", "member"]) {
      for (const targetGroup of [groupID, "missing-group"]) {
        await assertFails(setDoc(
          doc(firestoreFor(outsiderID), `groups/${targetGroup}/members/${outsiderID}`),
          { userID: outsiderID, displayName: "非成員", role, joinedAt: serverTimestamp() },
        ));
      }
    }
  });

  test("既有 member 與 leader 均不可從 Client 變更角色、UID 或加入時間", async () => {
    for (const actor of [uploaderID, leaderID]) {
      const reference = doc(firestoreFor(actor), `groups/${groupID}/members/${actor}`);
      for (const changes of [
        { role: actor === leaderID ? "member" : "leader" },
        { userID: outsiderID },
        { joinedAt: serverTimestamp() },
        { displayName: "新名字", role: "admin" },
      ]) {
        await assertFails(updateDoc(reference, changes));
        await assertFails(setDoc(reference, changes, { merge: true }));
      }
      await assertFails(updateDoc(
        doc(firestoreFor(actor), `groups/${groupID}/members/${teammateID}`),
        { role: "leader" },
      ));
    }
  });

  test("批次自建 member 並建立附件不能繞過 Rules，全部寫入都被拒絕", async () => {
    const firestore = firestoreFor(outsiderID);
    const batch = writeBatch(firestore);
    batch.set(doc(firestore, `groups/${groupID}/members/${outsiderID}`), {
      userID: outsiderID, displayName: "非成員", role: "member", joinedAt: serverTimestamp(),
    });
    batch.set(doc(firestore, attachmentPath), validFile({ uploaderID: outsiderID }));
    await assertFails(batch.commit());
    await assertFails(getDoc(doc(firestore, `groups/${groupID}`)));
  });

  test("移除成員身分後不能讀取或刪除自己原本上傳的附件", async () => {
    await seedAttachment();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await deleteDoc(doc(context.firestore(), `groups/${groupID}/members/${uploaderID}`));
    });
    await assertFails(getDoc(attachmentRef(uploaderID)));
    await assertFails(deleteDoc(attachmentRef(uploaderID)));
    await assertSucceeds(deleteDoc(attachmentRef(leaderID)));
  });

  test("附件所有路徑欄位與檔案 metadata 建立後皆不可修改", async () => {
    await seedAttachment();
    for (const changes of [
      { id: "other-id" }, { taskID: "other-task" }, { groupID: "other-group" },
      { originalFilename: "new-name.pdf" }, { contentType: "image/jpeg" },
      { byteSize: 2048 }, { externalURL: "https://example.org/other" },
      { kind: "image" }, { createdAt: serverTimestamp() }, { unexpected: true },
    ]) {
      await assertFails(updateDoc(attachmentRef(uploaderID), changes));
    }
  });

  test("附件缺少必要欄位、多餘欄位或嵌套路徑均拒絕", async () => {
    const missingTitle = validFile();
    delete missingTitle.title;
    await assertFails(setDoc(attachmentRef(uploaderID), missingTitle));
    await assertFails(setDoc(attachmentRef(uploaderID), validFile({ unexpected: true })));
    await assertFails(setDoc(attachmentRef(uploaderID), validFile({
      storagePath: safeStoragePath.replace("report-", "nested/report-"),
    })));
    await assertFails(setDoc(attachmentRef(uploaderID), validFile({ title: "" })));
  });

  test("成員可建立所有允許的檔案種類與 20 MB 邊界 metadata", async () => {
    const types = [
      ["image", "image/jpeg", "jpg"], ["image", "image/png", "png"],
      ["pdf", "application/pdf", "pdf"],
      ["document", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx"],
      ["spreadsheet", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"],
      ["presentation", "application/vnd.openxmlformats-officedocument.presentationml.presentation", "pptx"],
      ["archive", "application/zip", "zip"], ["archive", "application/x-zip-compressed", "zip"],
    ];
    for (const [index, [kind, contentType, extension]] of types.entries()) {
      const id = `allowed-${index}`;
      const path = `groups/${groupID}/tasks/${taskID}/attachments/${id}`;
      await assertSucceeds(setDoc(attachmentRef(uploaderID, path), validFile({
        id, kind, contentType, originalFilename: `result.${extension}`,
        byteSize: 20 * 1024 * 1024,
        storagePath: `${path}/result-a1b2c3d4.${extension}`,
      })));
    }
  });
});

describe("匿名互評資料隔離", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      await setDoc(doc(firestore, `groups/${groupID}/peerReviewStates/${uploaderID}`), {
        reviewedUIDs: [teammateID],
        completed: false,
      });
      await setDoc(doc(firestore, `groups/${groupID}/peerReviewPublic/summary`), {
        totalReviewCount: 1,
        completedReviewerCount: 0,
      });
      await setDoc(doc(firestore, `groups/${groupID}/peerReviewSubmissions/private-review`), {
        reviewerUID: uploaderID,
        revieweeUID: teammateID,
      });
      await setDoc(doc(firestore, `groups/${groupID}/peerReviewAggregates/summary`), {
        totalReviewCount: 1,
      });
      await setDoc(doc(firestore, `groups/${groupID}/peerReviewComments/${uploaderID}`), {
        comments: ["合作過程很可靠"],
      });
    });
  });

  test("成員只能讀取自己的互評進度", async () => {
    await assertSucceeds(getDoc(doc(
      firestoreFor(uploaderID),
      `groups/${groupID}/peerReviewStates/${uploaderID}`,
    )));
    await assertFails(getDoc(doc(
      firestoreFor(teammateID),
      `groups/${groupID}/peerReviewStates/${uploaderID}`,
    )));
  });

  test("群組成員可讀匿名摘要，非成員不可讀", async () => {
    const path = `groups/${groupID}/peerReviewPublic/summary`;
    await assertSucceeds(getDoc(doc(firestoreFor(teammateID), path)));
    await assertFails(getDoc(doc(firestoreFor(outsiderID), path)));
  });

  test("原始互評與私有統計不開放給任何用戶端", async () => {
    await assertFails(getDoc(doc(
      firestoreFor(uploaderID),
      `groups/${groupID}/peerReviewSubmissions/private-review`,
    )));
    await assertFails(getDoc(doc(
      firestoreFor(uploaderID),
      `groups/${groupID}/peerReviewAggregates/summary`,
    )));
  });

  test("成員只能讀取自己收到的匿名評語", async () => {
    const ownCommentsPath = `groups/${groupID}/peerReviewComments/${uploaderID}`;
    await assertSucceeds(getDoc(doc(firestoreFor(uploaderID), ownCommentsPath)));
    await assertFails(getDoc(doc(firestoreFor(teammateID), ownCommentsPath)));
    await assertFails(getDoc(doc(firestoreFor(outsiderID), ownCommentsPath)));
  });

  test("互評狀態與摘要只能由後端寫入", async () => {
    await assertFails(setDoc(doc(
      firestoreFor(uploaderID),
      `groups/${groupID}/peerReviewStates/${uploaderID}`,
    ), { reviewedUIDs: [], completed: false }));
    await assertFails(setDoc(doc(
      firestoreFor(uploaderID),
      `groups/${groupID}/peerReviewPublic/summary`,
    ), { totalReviewCount: 999, completedReviewerCount: 999 }));
    await assertFails(setDoc(doc(
      firestoreFor(uploaderID),
      `groups/${groupID}/peerReviewComments/${uploaderID}`,
    ), { comments: ["偽造評語"] }));
  });
});

test('profile photo metadata belongs to its account', async () => {
  const path = `profiles/${uploaderID}`;
  const value = {avatarPath: `avatars/${uploaderID}/12345678-1234-1234-1234-123456789abc.jpg`};
  await assertSucceeds(setDoc(doc(firestoreFor(uploaderID), path), value));
  await assertFails(getDoc(doc(firestoreFor(teammateID), path)));
  await assertFails(getDoc(doc(firestoreFor(null), path)));
  await assertFails(setDoc(doc(firestoreFor(teammateID), path), value));
  await assertFails(setDoc(doc(firestoreFor(uploaderID), path), {avatarPath: `avatars/${teammateID}/12345678-1234-1234-1234-123456789abc.jpg`}));
});

test('members can publish only their own group avatar path', async () => {
 const path = `groups/${groupID}/members/${uploaderID}`;
 const value = {avatarPath: `groups/${groupID}/avatars/${uploaderID}/avatar.jpg`, avatarVersion: 'v1'};
 await assertSucceeds(updateDoc(doc(firestoreFor(uploaderID), path), value));
 await assertFails(updateDoc(doc(firestoreFor(teammateID), path), value));
 await assertFails(updateDoc(doc(firestoreFor(uploaderID), path), {...value, avatarPath: `groups/${groupID}/avatars/${teammateID}/avatar.jpg`}));
});

test('join application inbox is leader-only; applicant can read only their own result', async () => {
  const inbox = `groups/${groupID}/joinRequests/${outsiderID}`;
  const result = `users/${outsiderID}/groupJoinRequests/${groupID}`;
  const history = `users/${outsiderID}/peerReviewProjects/past`;
  await testEnv.withSecurityRulesDisabled(async ctx => {
    for (const path of [inbox, result]) await setDoc(doc(ctx.firestore(), path), {status:'pending',applicantID:outsiderID});
    await setDoc(doc(ctx.firestore(), history), {reviewCount:2});
  });
  await assertSucceeds(getDoc(doc(firestoreFor(leaderID), inbox)));
  await assertSucceeds(getDoc(doc(firestoreFor(outsiderID), result)));
  for (const uid of [uploaderID, outsiderID, null]) await assertFails(getDoc(doc(firestoreFor(uid), inbox)));
  for (const uid of [leaderID, uploaderID, null]) await assertFails(getDoc(doc(firestoreFor(uid), result)));
  await assertFails(getDoc(doc(firestoreFor(outsiderID), `groups/${groupID}`)));
  // Sharing is scoped through the authorized callable, never blanket access to history.
  await assertFails(getDoc(doc(firestoreFor(leaderID), history)));
  for (const uid of [leaderID, outsiderID]) {
    await assertFails(setDoc(doc(firestoreFor(uid), inbox), {status:'approved'}));
    await assertFails(setDoc(doc(firestoreFor(uid), result), {status:'approved'}));
  }
});
