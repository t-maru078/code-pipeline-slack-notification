# code-pipeline-slack-notification

CodePipeline で発生するイベントを Slack に通知するサンプルです。

CloudFormation template を使って AWS リソースを定義しているため必要な環境をコマンド 1 つでデプロイ可能です。

今回は CodePipeline のイベントを通知するように設定していますが、通知対象の Event ID を変更することで CodeBuild など他のイベント通知にも利用できます。通知で設定できるイベントの詳細は下記の公式ドキュメントを参照してください。

https://docs.aws.amazon.com/dtconsole/latest/userguide/concepts.html#concepts-api


## CI 部分の構成図

![workflow](./docs/assets/workflow.jpg)


## AWS へのデプロイ

事前に下記の作業 3 つが必要です。

1. AWS CLI のインストール。詳細は下記の公式ドキュメント参照。

    https://docs.aws.amazon.com/ja_jp/cli/latest/userguide/getting-started-install.html

1. GitHub にて Personal access token を取得する。詳細は下記の公式ドキュメント参照。

    https://docs.aws.amazon.com/ja_jp/codebuild/latest/userguide/access-tokens.html

1. 上記で取得した token をデプロイコマンド実行前に AWS の Management Console で設定する

    1. CodeBuild の console を開き `Create build project` ボタンを押す
    1. Source provider のドロップダウンから `GitHub` を選択する
    1. `Connect with a GitHub personal access token` を選択し、`GitHub personal access token` の欄に GitHub から取得した Personal access token を入力し `Save token` ボタンを押す
    1. console 最下部の `cancel` ボタンを押して `Create build project` のウィザードを閉じる

1. AWS Chatbot コンソールを開き、Slack workspace との接続を行う

    1. `Configure a chat client` のセクションで Chat client から　Slack を選択し、`Configure client` を押す
    1. Slack の設定画面が開き AWS からのアクセスを許可するかどうかを尋ねられるので、内容を確認し問題なければ Allow をクリックする

1. `scripts/env.template` をコピーして `scripts/.env` ファイルを作成し、必要なパラメータを記載する

    | Parameter name | Description | Required |
    |--|--|--|
    | TEMPLATE_STORE_S3_BUCKET_NAME | CloudFormation template を格納する S3 バケット。<br />ここで指定した S3 に対してデプロイスクリプトが必要な template を動的にアップロードします。 | Yes |
    | GITHUB_REPOSITORY_URL | Pipeline をトリガーする GitHub リポジトリの URL | Yes |
    | SLACK_WORKSPACE_ID | 通知対象の Channel がある Slack workspace の ID | Yes |
    | SLACK_CHANNEL_ID | 通知対象の Channel の ID | Yes |
    | AWS_PROFILE | AWS CLI 実行時に使用する AWS の Profile。<br />指定しない場合は default profile が使用されます。 | No |

上記の手順が完了後、この README と同じディレクトリ階層で下記コマンドを実行することで必要な環境が AWS 上にデプロイされます。

```
bash scripts/deploy-pipeline.sh
```

## 注意事項

- このサンプルは GitHub Apps などを設定する必要がなく上記のコマンドを使って AWS リソースをデプロイするだけで使用可能になりますが、GitHub の Webhook により起動される CodeBuild の Container は Pipeline 処理が完了か timeout するまで起動し続けますので、ビルドやテストなどに時間がかかるアプリケーションの場合 CodeBuild の料金がかさむ可能性がありますのでご注意ください。

- CloudFormation stack の削除時に不要な S3 リソースが残らないように DeletionPolicy は設定しておりません。Pipeline 実行後は S3 内部にファイルが作成されておりますので stack の削除時に DELETE_FAILED 状態になりますが S3 内部のファイルを削除 (Object のすべての version を削除) してから再度 stack の削除を実行すると正常に削除されます。
