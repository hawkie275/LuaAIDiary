# インフラ更新の検証

## 実行方法

- `make test-infra`: version解析、状態保存、named volume取得と、隔離Gitによる配備資材・外部設定保持・失敗伝播の確認。
- `make test-infra-docker`: 専用random projectで新規導入後、PG18→19とValkey更新を実行。データ、所有者、sequence、migration台帳、session値・TTL、旧volumeの保持を確認。
- Docker試験はloopbackのランダムportとnginx fixtureを使用。共有networkにpeerを1台置き、試験自身の資産だけを後片付けする。ローカル専用の使い捨てDocker環境でのみ実行する。

ワークフロー模倣、障害注入、内部journalの書換え、重複更新試験は削除した。
過去版の実行記録は現行版の検証結果ではない。現行版の実行結果は今回の作業報告に記載する。
本番CD、リモート配備、アプリ全機能、電源断・disk fullはこの最小試験の対象外。
