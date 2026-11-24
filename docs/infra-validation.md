# インフラ更新の提供版確認・検証記録

確認日: 2026-11-24 UTC。実環境: Linux arm64 / Debian 13、Docker Engine 29.10.0、
Docker Compose 5.8.0、jq 1.7、util-linux 2.41.5、GNU coreutils 9.7。

## 公式レジストリ提供状況

Docker Hub公式APIへHTTPSで問い合わせ、続けてDocker pullとコンテナ内のversionコマンドで確認した。
将来のタグ内容を保証するものではなく、この日時の観測値。

| 問合せ先 | 結果 / index digest |
|---|---|
| https://hub.docker.com/v2/repositories/library/postgres/tags/19 | 提供あり、sha256:908d19593a1444b2d4e85783f718b16e0d40f1baf7518420475df9e5f5ac67a2 |
| https://hub.docker.com/v2/repositories/library/postgres/tags/latest | 同じdigest、19と一致 |
| https://hub.docker.com/v2/repositories/valkey/valkey/tags/latest | 提供あり、sha256:1c2b25b09f354c66fe994733acdf12fcfd4bdf6f3bd92b88a93a70378d884056 |

- PostgreSQL 19タグのlast_updated: 2026-11-24T01:08:50.808174Z。
- Valkey latestタグのlast_updated: 2026-11-19T19:52:09.121805Z。
- PostgreSQL 19 APIにはamd64、arm64/v8等、Valkeyにはamd64、arm64等を確認。
- `docker run --rm --network none postgres:19 postgres --version`:
  `postgres (PostgreSQL) 19.0 (Debian 19.0-2.pgdg13+1)`。
- `docker run --rm --network none valkey/valkey:latest valkey-server --version`:
  `Valkey server v=9.2.0 sha=00000000:0 malloc=jemalloc-5.3.0 bits=64 build=f1b6626b8181bb44`。
- 未提供時の処理はpull失敗を伝播し停止。実装には旧版fallbackを設けていない。

07:45:45 UTCに再確認したところ、PG19タグは07:12:08.985084Z更新の
`sha256:e99b33203b969310f42fd7edf8b3a295ee81a9909a3e2569b3ce87f25b1f4ca0` に変化していた。
実行versionは引き続き19.0。タグが更新されても通常起動は記録済みdigestを使用し、
更新入口を明示的に呼んだときだけ新digestを採用する必要性も確認できた。

## 検証方法

- [単体・障害系テスト](../tests/infra/test_unit.sh): version解析、downgrade拒否、状態保存、mount検査、
  SQL失敗伝播、未固定の通常起動拒否、中断journalの起動拒否。
- [実Dockerテスト](../tests/infra/test_docker.sh): 独立random project、loopbackのランダムportのみ、
  実PostgreSQL/Valkeyを使用。Webはnginxのテスト用imageで、公開制御の確認に限定。
  アプリの全機能テストや本番配備テストではない。
- テストだけが作ったprefixのコンテナ・volume・networkのみ後片付けする。
  既存のluaaidiary-web/db/valkeyおよび既存volumeは変更・削除しない。
- UI変更なし。Chromeによる画面確認はこの変更の検証対象外と判断し実施しない。

## 開発中に検出・修正した問題

最初の実Docker移行で、別名のinitdb bootstrap roleからの所有権再割当てがPostgreSQLの
システム依存により拒否された。公開前に停止することを確認し、元と同名の管理roleで初期化し、
そのCREATE文1件だけを厳密に除外してglobalsを復元する方式へ修正した。

Valkey 9.2の標準Lua moduleを外部moduleと誤認するguardも実Dockerで検出し修正した。
外部moduleは引き続き拒否する。途中の実行では実行中テストファイル編集による末尾読込エラーもあり、
その実行を完走成功として扱わず、確定したファイルで再実行する。

## 最終実行結果（2026-11-24 07:48〜07:51 UTC）

| 検査 | 結果 |
|---|---|
| Bash構文検査（scripts / tests/infra） | 成功 |
| git diff --check | 成功 |
| ShellCheck（koalaman/shellcheck:stable） | 全追加Shellファイルで警告・エラーなし |
| actionlint（rhysd/actionlint:latest） | release-deploy workflowでエラーなし |
| 単体・障害系 | 18項目成功 |
| 隔離GitによるCD資材配備テスト | 同commit配備・外部state・環境/override保護・失敗伝播・ポインタ維持を確認 |
| 実Docker移行試験 | **終了コード0、全項目成功** |

実Docker試験では以下を確認した。

1. 実init SQLと既存migrationによる新規導入（PG18 / Valkey9.0.0）。
2. PostgreSQL 18→19、Valkey 9.0.0→9.2.0の実移行。
3. データ、role、所有者、sequence継続値、既存migration台帳2件、session値/残存TTLの保持。
4. 旧DB/Valkey volumeの存在、同一メジャー更新でも別の復旧用volumeを保持。
5. 追加DBを拒否、downgradeを拒否。
6. 存在しないPostgreSQL 999999希望版を停止前に拒否し、旧DBへの接続継続を確認。fallbackなし。
7. SQL migrationの意図的エラーを伝播し、Web停止・未完了journalによる通常起動拒否を確認。
8. 公開前の明示的復旧後、元データとsessionを確認。
9. publishing状態を模擬したjournalでは明示的復旧も拒否。

最終テストの固有project: `infra-test-1795506500-5939`。
ローカル証跡: `/tmp/luaaidiary-infra-docker-test-final.log`、
`/tmp/luaaidiary-infra-test.O5gNfA`（state、backup、失敗注入ログを保持）。
これらはローカル一時領域であり、将来の保持を保証しない。
テスト専用コンテナ・volume・networkは終了時に後片付けした。imageは削除していない。
既存luaaidiary-web/db/valkeyは試験終了後も約8時間の継続稼働を確認。既存volumeの変更・削除は実施していない。

## 未検証・制限・レビュー重点

- 実GitHub Actionsのproduction配備、GHCRへのbuild/push、承認フローは未実行。
  workflow静的検査と隔離Git資材配備試験まで。
- 実Dockerはarm64のみ。amd64の提供確認はAPIで行ったが、その上での移行は未実行。
- PostgreSQL 20の実imageによる移行は未実行。19→20比較は単体テストで確認したが、
  将来版のextension/collation互換性や実restore成功はリリース時に検証が必要。
- 自動Docker試験のWebはnginx image。下記の承認済みローカル実環境試験では実WebのHTTP応答と
  Chromium表示も確認。ログイン実行・投稿・media操作と性能確認は未実行。
- 未完了journalの拒否を確認したが、全命令境界でのSIGKILL、実host電源断、disk full、
  大規模DB、外部writerとの競合、復旧中の再故障の網羅試験は未実行。
- 原子的設定置換とsyncはLinuxローカルfilesystem前提。NFSや複数host運用には対応しない。
- 既存の標準公開DB/Valkey portはCD内で停止して採用可能（下記追検証を参照）。書込み遮断宣言、
  固定project/専用Unixユーザー/外部state、backupの機密性と容量をレビューすること。
- 未pushのローカルWeb imageによる管理起動は非対応。従来のsetup-build経路は安全上停止する。
- 公開後の旧volumeへの自動巻戻しは禁止。未対応DB/Valkeyカスタマイズは別の移行計画が必要。

## 引継ぎ後の追検証（2026-11-24 08:11〜08:21 UTC）

### 修正と隔離試験

- 旧コンテナの標準data port公開を受け入れ、全image準備・復旧記録保存後に旧Web/DB/Valkeyを
  停止し、正常停止・restart無効を確認した後だけコピーする。移行先data port禁止は維持。
- 未知のnetwork peerに加え、旧volumeを共有する別コンテナも拒否。
- 停止段階での通常エラー・捕捉可能な中断は残りの旧サービスも停止試行する。
  lock取得失敗など、停止段階を所有しないプロセスは他の配備を操作しない。
- Bash構文、diff空白検査、ShellCheck、actionlint成功。ShellCheck初回はコンテナの作業directory
  指定漏れで実行できず、`-w /src` を指定して再実行し成功。
- 単体・障害系 **24項目成功**、隔離GitによるCD資材配備テスト成功。
- Docker試験 **終了コード0、全項目成功**。project: `infra-test-1795507905-21510`。
  証跡: `/tmp/luaaidiary-infra-followup.log`、`/tmp/luaaidiary-infra-test.NxSkRy`。
  標準公開portの旧構成をloopbackランダムportで再現し、未知writer拒否、migration失敗時の
  全旧サービス停止、通常起動拒否、旧データへの明示復旧とdata port非公開化、公開旧構成からの
  PG18→19 / Valkey9.0.0→9.2.0成功を追加確認。従来のデータ・role・sequence・TTL保持、
  同major更新、未提供版・downgrade拒否、公開後rollback拒否も成功。

### 公式提供版の再確認

08:11 UTCのDocker Hub API結果:

| 対象 | 結果 |
|---|---|
| library/postgres:19 | HTTP 200、sha256:e99b33203b969310f42fd7edf8b3a295ee81a9909a3e2569b3ce87f25b1f4ca0 |
| library/postgres:20 | **HTTP 404（未提供）** |
| valkey/valkey:latest | HTTP 200、sha256:1c2b25b09f354c66fe994733acdf12fcfd4bdf6f3bd92b88a93a70378d884056 |

API証跡は `/tmp/luaaidiary-official-tags-followup.log`。実行versionはPG **19.0**、Valkey **9.2.0**。
PG19は実移行済み。PG20は未提供のため **19→20の実移行は未検証**。

### 利用者承認後の既存ローカル実環境試験

当初は既存サービスを変更せず、08:16 UTCにも3サービスの起動時刻・公開portが不変と確認した。
その後、利用者から「現在のローカルサービスを対象に更新テスト。停止・再作成を許可、旧データ保持」
の明示承認を受けて実行。ローカル試験のための追加コード変更は行っていない。

- 旧Webのregistry digestを指定し、Web image自体は変更せず共通更新入口を実行。
- transaction: `luaaidiary-20261124T081906-4455a62f`、最終phase **complete**。
- PostgreSQL 18→19.0、Valkey→9.2.0。DB/Valkeyはhealthy・ホストportなし、Webは8080で公開。
- 旧volume `luaaidiary_db_data` / `luaaidiary_redis_data` を保持。新volumeはtransaction名の別volume。
  logs/media volumeも維持。旧image保持タグ、元inspect、PGDATA、dump/復旧記録を保存。
- 復元前後fingerprint一致、globals/dumpのSHA256検証成功。
- `/health` はstatus ok、トップページと `/admin/login` はHTTP 200。
  初回の `/auth/login` は誤ったURLで404、実ルート確認後に再確認した。
- Chromium 156 headlessでトップページの投稿一覧を画像確認。
  日本語が四角表示となるため日本語描画の正常性は未確認（アプリHTMLには日本語が存在）。
  Google Chrome製品そのものではなく、このhostにあるChromiumを使用した。
- 証跡・画面: checkout外 `../.luaaidiary-state/local-validation-20261124T081857/`。
  dump・旧inspect等: `../.luaaidiary-state/luaaidiary-20261124T081906-4455a62f/`。
  いずれも秘密情報を含み得るため公開しない。

追加の注意: 複数RepoDigestsを持つimageで先頭の保持用repository別名がruntimeへ記録されることを
確認した。このhostでの更新・起動は成功したが、正規registry名を選択する改善案は利用者が追加変更を
希望しなかったため未適用。stateだけを別hostへ移してpullできることは保証しない。
単一host前提とimage/backup保持を守り、他host復旧には正規registry digestの別途確認が必要。
