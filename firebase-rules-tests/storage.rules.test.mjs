import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";
import {
  deleteObject,
  getBytes,
  ref,
  updateMetadata,
  uploadBytes,
} from "firebase/storage";

const projectId = "demo-group-bomb";
const groupID = "group-alpha";
const taskID = "task-one";
const attachmentID = "attachment-one";
const uploaderID = "member-uploader";
const teammateID = "member-teammate";
const leaderID = "member-leader";
const outsiderID = "outsider";
const validPath =
  `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}/report-a1b2c3d4.pdf`;

let testEnv;

function storageFor(userID) {
  return userID
    ? testEnv.authenticatedContext(userID).storage()
    : testEnv.unauthenticatedContext().storage();
}

function upload(storage, path, contentType, ownerID, bytes = new Uint8Array([1])) {
  return uploadBytes(ref(storage, path), bytes, {
    contentType,
    customMetadata: { uploaderID: ownerID },
  });
}

async function seedMember(userID, role = "member") {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), `groups/${groupID}/members/${userID}`),
      { role },
    );
  });
}

async function seedFile(path = validPath, ownerID = uploaderID) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await upload(context.storage(), path, "application/pdf", ownerID);
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({ projectId });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await seedMember(uploaderID);
  await seedMember(teammateID);
  await seedMember(leaderID, "leader");
});

after(async () => {
  await testEnv.cleanup();
});

describe("Group Bomb Storage Security Rules", () => {
  test("未登入使用者不可上傳或下載", async () => {
    await assertFails(
      upload(storageFor(), validPath, "application/pdf", uploaderID),
    );
    await seedFile();
    await assertFails(getBytes(ref(storageFor(), validPath)));
  });

  test("群組成員可下載，非成員不可下載", async () => {
    await seedFile();
    await assertSucceeds(getBytes(ref(storageFor(teammateID), validPath)));
    await assertFails(getBytes(ref(storageFor(outsiderID), validPath)));
  });

  test("群組成員可上傳允許的 MIME 與相符副檔名", async () => {
    const cases = [
      ["photo-a1b2c3d4.jpg", "image/jpeg"],
      ["photo-a1b2c3d4.png", "image/png"],
      ["report-a1b2c3d4.pdf", "application/pdf"],
      ["document-a1b2c3d4.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"],
      ["sheet-a1b2c3d4.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"],
      ["slides-a1b2c3d4.pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation"],
      ["archive-a1b2c3d4.zip", "application/zip"],
      ["archive-b1c2d3e4.zip", "application/x-zip-compressed"],
    ];

    for (const [fileName, contentType] of cases) {
      const path =
        `groups/${groupID}/tasks/${taskID}/attachments/${fileName}/${fileName}`;
      await assertSucceeds(
        upload(storageFor(uploaderID), path, contentType, uploaderID),
      );
    }
  });

  test("非群組成員不可上傳", async () => {
    await assertFails(
      upload(storageFor(outsiderID), validPath, "application/pdf", outsiderID),
    );
  });

  test("超過 20 MB 或空檔案不可上傳", async () => {
    const oversized = new Uint8Array(20 * 1024 * 1024 + 1);
    await assertFails(
      upload(storageFor(uploaderID), validPath, "application/pdf", uploaderID, oversized),
    );
    await assertFails(
      upload(storageFor(uploaderID), validPath, "application/pdf", uploaderID, new Uint8Array()),
    );
  });

  test("不支援的 MIME、MIME 與副檔名不符均不可上傳", async () => {
    await assertFails(
      upload(storageFor(uploaderID), validPath, "video/mp4", uploaderID),
    );
    await assertFails(
      upload(storageFor(uploaderID), validPath, "image/jpeg", uploaderID),
    );
  });

  test("不可偽造 uploaderID，也不可使用不安全檔名或其他路徑", async () => {
    await assertFails(
      upload(storageFor(uploaderID), validPath, "application/pdf", teammateID),
    );
    const unsafePath =
      `groups/${groupID}/tasks/${taskID}/attachments/${attachmentID}/我的 報告.pdf`;
    await assertFails(
      upload(storageFor(uploaderID), unsafePath, "application/pdf", uploaderID),
    );
    await assertFails(
      upload(storageFor(uploaderID), "public/report-a1b2c3d4.pdf", "application/pdf", uploaderID),
    );
  });

  test("既有檔案內容與 metadata 不可更新", async () => {
    await seedFile();
    await assertFails(
      updateMetadata(ref(storageFor(uploaderID), validPath), {
        customMetadata: { uploaderID: teammateID },
      }),
    );
    await assertFails(
      upload(storageFor(uploaderID), validPath, "application/pdf", uploaderID),
    );
  });

  test("原上傳者可刪除，一般成員不可刪除別人的檔案", async () => {
    await seedFile();
    await assertFails(deleteObject(ref(storageFor(teammateID), validPath)));
    await assertSucceeds(deleteObject(ref(storageFor(uploaderID), validPath)));
  });

  test("leader 可以刪除其他成員上傳的檔案", async () => {
    await seedFile();
    await assertSucceeds(deleteObject(ref(storageFor(leaderID), validPath)));
  });
});

test('private profile photos: only owner reads and uploads', async () => {
  const path = `avatars/${uploaderID}/12345678-1234-1234-1234-123456789abc.jpg`;
  await assertSucceeds(upload(storageFor(uploaderID), path, 'image/jpeg', uploaderID));
  await assertFails(getBytes(ref(storageFor(teammateID), path)));
  await assertFails(getBytes(ref(storageFor(null), path)));
  await assertFails(upload(storageFor(teammateID), path, 'image/jpeg', teammateID));
});

test('group avatars are readable only by members and writable only by owner', async () => {
 const path = `groups/${groupID}/avatars/${uploaderID}/avatar.jpg`;
 await assertSucceeds(upload(storageFor(uploaderID), path, 'image/jpeg', uploaderID));
 await assertSucceeds(getBytes(ref(storageFor(teammateID), path)));
 await assertFails(getBytes(ref(storageFor(outsiderID), path)));
 await assertFails(upload(storageFor(teammateID), path, 'image/jpeg', teammateID));
});
