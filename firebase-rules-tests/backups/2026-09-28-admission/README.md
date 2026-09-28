# 入群審核部署備份

專案：`group-bomb`；區域：`asia-east1`。

- `firestore-before.rules`：部署前正式規則；ruleset 為 `projects/group-bomb/rulesets/ecade35d-b94b-42fd-99cd-69970d48ce65`。
- `firestore-deployed.rules`：本次部署規則。與部署前相比，只增加組長讀取群組申請、申請者讀取自己申請狀態的規則；Client 不能寫入。
- 正式 `/groups/{groupID}/smartAgenda/{agendaID}` 讀取條件為 `isGroupMember(groupID)`；本機主規則檔另有 `agendaID == 'current'` 限制。這是部署前既存差異，本次保留正式條件，不連帶部署此差異。

這些檔案不含使用者資料或登入憑證。回復規則前須先確認入群 API 與已產生申請的處理方式，避免只撤除權限而留下運作中的審核流程。
