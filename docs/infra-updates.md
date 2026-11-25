# PostgreSQL / Valkey 更新運用 / Infrastructure updates

## 概要と依存

共通入口は [scripts/infra-update.sh](../scripts/infra-update.sh)、CD資材配備は
[scripts/deploy-release.sh](../scripts/deploy-release.sh)。Pythonは不要です。
Linux、Bash 5以上、jq 1.6以上、util-linuxのflock、GNU coreutils（sync -f、sort -V、realpath、mktemp、cmp）、
awk、grep、sed、tar、Git、Docker Engine、Docker Compose **2.24.4以上**を必要とします。
Debian系では管理者が `apt-get install bash jq util-linux coreutils git tar` で依存を準備してください。
Docker socketへのアクセスはroot相当の権限です。専用の信頼できるrunner/Unixユーザーを使ってください。

通常起動と更新は分離します。希望版の既定はPostgreSQL **19**、Valkey **latest（安定版）**。
`.env`の `POSTGRES_DESIRED_VERSION=latest` を選べば将来の最新安定メジャーにも追従します。
タグを再解決するのは `make infra-update` またはCD実行時だけで、定期的な自動pollはしません。
追従希望の場合はCDの手動実行でも最新版を再解決できます。19→20専用分岐はありません。
希望タグのpull失敗、未提供、非安定版のバージョン出力は停止します。18等への暗黙fallbackはありません。

実稼働のimage digest、volume名、PGDATAはcheckout外の `active.json` に原子的に固定します。
通常の `make up` はその固定値を使い、希望タグの変更で新しい空DBを起動しません。
固定値がない直接の `docker compose up` は必須変数エラーになります。手動でこれを迂回しないでください。
更新時は同一メジャー・同一digestでも別volumeへ復元し、SQL migration失敗の巻戻し用データを確保します。
停止時間と十分な空き容量が必要です。無停止更新の仕組みではありません。

## 対応範囲・運用上の必須条件

- 固定projectの単一Compose（web/db/valkeyだけ）、単一Docker host、単一運用Unixユーザー。
  `COMPOSE_PROJECT_NAME=luaaidiary` が既定です。既存コンテナのCompose projectラベルと一致させます。
  CDのprojectも固定しています。異なる既存projectを使っている場合は導入前に設定を揃えてください。
- DBは `/var/lib/postgresql` を親としてmountしたローカルnamed volume、実PGDATAはその配下。
  コンテナの実mount、実PGDATA、PG_VERSION、サーバーdata_directoryを確認します。
  コンテナ不在の既存volume、bind mount、追加mount、不明なレイアウトは推測せず停止します。
- アプリDBひとつと標準のpostgres/template DB。設定ユーザーは元のinitdb管理role（OID 10）であること。
  追加DB、追加template、独自tablespace、prepared transaction、replication slot、publication、subscription、
  foreign server、標準以外の拡張は検出して停止します。対応拡張はplpgsqlとpg_trgm。
  postgres/template1のユーザースキーマ・テーブル・関数・追加拡張も拒否します。
  独自のmaintenance/template設定、サーバー設定変更、特殊なcollation/外部依存は対象外です。
  汎用PostgreSQLクラスタ移行器ではありません。事前にDBAが対応範囲を確認してください。
- role属性・パスワード・membershipはglobals dump、アプリの所有者・ACL・拡張・sequence・large object・
  migration履歴は通常の完全dump/restoreで保存します。初期管理roleのCREATE文1件だけを除外し、
  そのALTER文やGRANTは除外しません。復元前後の行数・sequence値/状態・所有者・拡張名を照合します。
- Valkeyは単一master、replicaなし、cluster/外部moduleなし（標準Lua moduleは許可）、AOFなし、標準 `/data/dump.rdb`。
  カスタムcommand/entrypointは拒否します。独自ACL・CONFIG変更・永続化設定を使う構成は対象外です。
  SAVE成功後に正常停止し、別volumeへ全ファイルをコピーします。RDBの絶対期限を維持するためsession TTLは
  更新中も経過します。期限切れセッションが復活することはありません。
- **標準単一Compose構成は自動でwriterを停止・隔離します。** 全image準備後、旧Web/DB/Valkeyの
  restartを無効化し、Web正常停止、Valkey SAVE、DB/Valkey正常停止を順に実施します。
  全旧サービスの停止・終了コード0・OOMなし・restart無効と未知volume利用者不在を確認してから、
  停止済み原本を別volumeへコピーします。隔離コピーでdump/restoreとmigration・検証を行い、
  切替直前にも全原本の停止・restart無効、未知network/volume利用者不在を再確認します。
  旧標準5432/tcp・6379/tcp公開は停止で閉じるため、手作業のport除去は不要です。
  host/container network、非標準port、自動全port公開、未知network peer、別volume利用者
  （停止中を含む）は拒否します。新側DB/Valkeyは非公開で起動し、最後にWebを公開します。
  `INFRA_WRITERS_FENCED` は不要で、残存設定の値は無視します。削除・移行作業は不要です。
  Docker管理権限で原本を再起動・execできる悪意プロセスや、管理外の自動起動ツールとの競合を
  保証する仕組みではありません。標準構成に毎回の手動writer宣言は要求しません。
- host lockと状態lockはflockです。全入口で同一Unixユーザー・project・stateを使うこと。
  別ユーザー、別Docker host、NFS共有state、手動Docker操作に対する分散lockではありません。
- state/backupは0700/0600で保護しますが**暗号化されません**。DB全データ、role password hash、
  inspectに含まれる環境変数が保存されます。暗号化ディスク、別媒体backup、容量監視が必要です。
  旧DB、旧Valkey、旧PGコピー、新DB、新Valkey、論理dumpが並存する容量を事前に確保してください。
  自動prune/volume削除は禁止です。旧imageには保持用タグを付けますが `image prune -a` からは保護できません。

## 初回導入

```bash
cp .env.example .env
# .envのパスワード等を編集する
export INFRA_STATE_DIR=/srv/luaaidiary/state
export COMPOSE_PROJECT_NAME=luaaidiary
# 標準構成の停止・隔離は自動制御（手動writer宣言は不要）:
make setup
```

新規導入は明示的な初期化モードを使います。既存コンテナや既存の標準data volumeがある場合は拒否します。
初期SQLをmountするのはこの新規導入時だけです。通常Composeおよび移行先にはinit SQLをmountしません。
移行先にinit SQLを再投入して既存migration台帳やデータを上書きすることはありません。
Webはregistry digestを持つimageを利用します。独自Webのローカルbuildはregistryへpushしてから
`DEPLOY_WEB_IMAGE=registry/name:tag make setup` を使用してください。未pushのローカルimageによる管理起動は対象外です。

## 既存PG18 / Valkey9の採用

1. 別媒体backupを取り、既存projectラベル、実image ID、実named volume、PGDATA、設定を記録します。
2. **旧Composeの5432/6379公開はそのまま採用できます。事前のサービス停止・port除去は不要です。**
   新releaseの標準ComposeはDB/Valkeyを非公開にします。ユーザーoverrideで移行先にdata portを
   追加する構成は引き続き拒否します（overrideを勝手に書き換えることはありません）。
   CD実行時に全image準備→実image/volume/PGDATA/復旧記録の保存→旧Web停止→旧DB/Valkey正常停止→
   停止済みvolumeコピー→非公開隔離環境でdump/restore/検証/migration→非公開DB/Valkey→公開Webの順に進みます。
   復旧時も旧image・旧volumeを使いつつDB/Valkeyは非公開です。Web公開portは維持します。
3. 同じproject、認証情報、DB名、外部stateを設定し `make infra-update`。
   新規導入用の `make setup` / `--initialize` は使いません。
4. 起動後にアプリの健康状態、ログイン、投稿、media参照、監視を確認します。

## 更新の順序

1. lock取得、未完了journal検査、Compose/実コンテナ/対応範囲の検査。
2. PostgreSQL・Valkey・Webを**すべて事前pull**、digestと実行バージョンを確認。実バージョンのdowngradeを拒否。
   CDではWebのOCI revisionと配備commitが一致することも必須。
3. 永続journal、元のinspect、旧設定、旧image保持タグを記録。WebとDB/Valkeyの再起動policyを無効にしてWebを停止。
4. Valkey SAVE、全旧サービスの正常停止・restart無効を確認。停止済み旧DBをコピーし、networkなしの隔離したコピーを起動。
   対象版のclientを使ってglobalsとアプリDBの論理backupを保存。旧本体volumeは書き換えません。
5. 空の別DB volumeを対象版で初期化し復元。init SQLは使わず、復元検証後に既存migration runnerを対象版clientで実行。
   Web内のAlpine版pg clientには依存しません。SQLエラーは更新全体へ伝播します。
6. コピーしたValkeyを対象版で起動確認。隔離コンテナを正常停止し、固定設定を原子的に置換。
7. DB/Valkeyをhealth確認付きで起動。**publishingを永続化してから**Webを起動し、completeを保存。
   Web起動後のアプリ機能確認は別途必要です。Dockerの起動成功を全機能の正常性とはみなしません。

## 失敗・中断・復旧

未完了journalを見つけると、通常起動も更新も停止します。journalを削除して強制起動しないでください。
SIGKILLやhost再起動後もこのguardは有効です。最初の停止処理中に中断した場合は旧サービスが一部残る可能性があります。
通常エラー・捕捉可能なINT/TERMでは、停止段階を所有するプロセスだけが三サービスの停止を追加試行します。
SIGKILL、Docker daemon停止、host電源断ではその処理を保証できません。ただし両データサービスの
正常停止・restart無効の確認前にコピーや移行先公開へ進むことはありません。
それ以降の途中状態で自動的にWebを再公開する処理はありません。隔離コンテナはrestart=noです。

**公開前**（prepared/stopping/offline/restored/validated/switching）の失敗:

```bash
# 失敗時と同じrelease資材、.env、ユーザーoverride、project、stateを使用
make infra-recover
```

これは明示的な運用判断による復旧です。旧三サービスが記録されている場合だけ、現在のコンテナと隔離コンテナを停止し、
元のimage ID・元のvolume・元のPGDATAで起動します。設定が変わっていれば拒否します。
旧volumeは移行先へ書き込んだmigrationの影響を受けていません。target/backupは削除しません。
初回導入失敗には旧稼働環境がないためこの復旧は使えません。証跡を保全し個別に確認してください。

**publishing以降**はWebが書込みを受けた可能性があるため、明示的復旧も拒否します。
自動巻戻しは禁止です。Webをfenceし、新側データを保全してforward repairしてください。
完全な災害復旧はDBAの判断で行い、旧volumeへ戻すなら公開後の更新を失うことを評価してください。
再開のためのjournal修正は監査付きの個別復旧作業とし、通常の運用手順にしないでください。

## GitHub Actions / CD

[release-deploy.yml](../.github/workflows/release-deploy.yml) はbuildをGitHub-hosted、配備を
本番Docker host上のself-hosted runnerで実行します。production Environmentの承認・権限制御を推奨します。
Actions変数 `DEPLOY_PATH` にcheckout外の絶対パス（例 `/srv/luaaidiary`）を設定し、
そこへ `.env` と必要なら `docker-compose.override.yml` を運用者が事前配置してください。
DNS等のユーザー設定はこのoverrideに残します。旧 `LOCAL_DNS` 変数からoverrideを上書きする方式は廃止しました。
通常のmerge/CDだけでWeb/DB/Valkeyを更新します。writer宣言や追加のGitHub変数は不要です。

- Webをbuildしたcommitと同じCompose/scripts/docker/web/init SQL/migrationsを新release directoryへGit archiveで配備。
  `.env` とユーザーoverrideをコピー・上書きせず、その外部ファイルを読みます。
- state/backupは `DEPLOY_PATH/state`、releaseは `DEPLOY_PATH/releases`。checkout cleanupの影響を受けません。
- 同一concurrency group、cancel-in-progress=false。進行中配備を新ジョブがcancelしません。
  GitHubのconcurrencyは全pendingジョブをFIFOで保証するものではありません。
- 手動workflow_dispatchのrelease_tagに既存 `vX.Y.Z` を指定すると、そのtagのcommitとWebを照合して同じ入口を実行。
  この仕組み導入前でrevisionラベルのないWebは拒否します。導入後のreleaseを使用してください。
- 手動インフラ更新も希望タグを毎回解決します。Webは同じreleaseのまま、DB/Valkeyだけ最新版に追従できます。
- Actions上の実配備や本番資産の更新は開発テストには含めません。

## English operational summary

This is a single-host, offline logical migration, not a general HA upgrade framework. Both Make and
the self-hosted Actions runner call the same Bash entry point. Desired tags are separate from the
atomic digest/volume runtime pin. PostgreSQL defaults to 19; selecting latest follows future stable
majors without version-specific branches. Valkey defaults to latest stable; re-run CD to resolve it again.
Unavailable images, prereleases and downgrades fail without fallback.

All images are pulled before downtime. Existing named volumes and PGDATA are discovered, not guessed.
Old data is stopped cleanly and retained. An isolated cold copy supplies target-client logical dumps;
a fresh cluster restores globals, ownership, sequences, extensions and migration history. Init SQL runs
only on an explicitly new installation. Existing migrations run before publication using the target
PostgreSQL client. Valkey uses SAVE, clean stop and a separate volume copy preserving absolute TTLs.

No manual writer declaration is required; legacy values are ignored. Legacy standard published data ports are accepted: CD stops the
old services before copying data, and both migration and recovery start data services without host ports.
All original services are rechecked offline with restart disabled before switching. No manual service stop or port removal is required. Docker-administrator interference is outside this guarantee. Target Compose port overrides remain forbidden.
Only the three standard services,
one application database, standard maintenance/template databases, bundled plpgsql/pg_trgm, and standalone
RDB Valkey are supported. Unsupported features are rejected; customized server/template/ACL settings need
separate DBA review. Use the same Unix account, fixed Compose project and external state directory.
Backups contain secrets, require disk capacity and are never automatically pruned.

Interrupted journals block normal startup. Explicit infra-recover is allowed only before publishing and
only with unchanged configuration. Once publication begins, rollback is prohibited; use forward repair.
CD preserves user environment/override files and stages matching commit materials outside checkout.
The real Docker tests use an isolated random project and never touch existing production assets.
