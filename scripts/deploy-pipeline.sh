#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname $0)" || exit; pwd)
eval "$(cat ${SCRIPT_DIR}/.env <(echo) <(declare -x))"

: ==================================================
:  Constants
: ==================================================
PROJECT_NAME="code-pipeline-slack-notification"
S3_BUCKET_NAME=${TEMPLATE_STORE_S3_BUCKET_NAME:-$$-cfn-templates-store}
S3_PATH="s3://${TEMPLATE_STORE_S3_BUCKET_NAME}/${PROJECT_NAME}"
EXPIRE_DURATION=300
PIPELINE_TMPL_LIST="
ci-resources.yml
pipeline-resources/source-code-repository.yml
pipeline-resources/artifact-repository.yml
pipeline-resources/unit-tests-project.yml
pipeline-resources/pipeline.yml
pipeline-resources/github-webhook-project.yml
notification-resources/chatbot.yml
notification-resources/notifications.yml
"
[ -n "${AWS_PROFILE}" ] && AWS_CLI_OPTIONS="--profile ${AWS_PROFILE}"

: ==================================================
:  Functions
: ==================================================
function createS3Bucket() {
  local readonly s3BucketName=$1

  echo -e "    creating..."
  RESULT=$(aws ${AWS_CLI_OPTIONS} s3 mb s3://${s3BucketName}/ 2>&1)
  if [ $? -eq 0 ]; then
    echo -e "    The S3 Bucket(${s3BucketName}) successfully created.\n"
  else
    echo $RESULT | grep "BucketAlreadyOwnedByYou" 1>/dev/null
    if [ $? -eq 0 ]; then
      echo -e "    Using the existing S3 bucket(${s3BucketName}).\n"
    else
      echo -e "    The requested S3 bucket name(${s3BucketName}) is not available. Please check a name and try again!\n"
      exit 1
    fi
  fi
}

function validate() {
  error_flag=false

  for template in $(cat)
  do
    error=$(aws ${AWS_CLI_OPTIONS} cloudformation validate-template --template-body file://./ci/${template} 2>&1 > /dev/null)
    if [ $? -eq 0 ]
    then
      echo -e "      ${template} ----- \u001b[32m✔︎\u001b[0m"
    else
      error_flag=true
      echo -e "      ${template} ----- \u001b[31m✖︎\u001b[0m"
      echo -e "\u001b[31m${error}\u001b[0m\n"
    fi
  done

  if ${error_flag}
  then
    exit 1
  fi
}

function generateSignedUrl() {
  for TMPL in $(cat)
  do
    echo $(aws ${AWS_CLI_OPTIONS} s3 presign ${S3_PATH}/${TMPL} --expires-in $EXPIRE_DURATION)
  done
}

function createStack() {
  local readonly STACK_NAME=$1
  local readonly TEMPLATE=$2
  local readonly PARAMETERS=$3

  aws ${AWS_CLI_OPTIONS} \
    cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-url ${TEMPLATE} \
    --parameters ${PARAMETERS} \
    --capabilities CAPABILITY_NAMED_IAM \
    --on-failure DELETE
  aws ${AWS_CLI_OPTIONS} cloudformation wait stack-create-complete --stack-name ${STACK_NAME}
}

function updateStack() {
  local readonly STACK_NAME=$1
  local readonly TEMPLATE=$2
  local readonly PARAMETERS=$3

  aws ${AWS_CLI_OPTIONS} \
    cloudformation update-stack \
    --stack-name ${STACK_NAME} \
    --template-url ${TEMPLATE} \
    --parameters ${3} \
    --capabilities CAPABILITY_NAMED_IAM
  aws ${AWS_CLI_OPTIONS} cloudformation wait stack-update-complete --stack-name ${STACK_NAME}
}

: ==================================================
:  Main
: ==================================================
echo -e "\n  deploy pipeline starting...\n"
echo -e "    [1] Create S3 Bucket\n"
createS3Bucket ${TEMPLATE_STORE_S3_BUCKET_NAME}
[ $? -ne 0 ] && exit 1

echo -e "    [2] validate CFn templates \n"
echo ${PIPELINE_TMPL_LIST} | validate
[ $? -ne 0 ] && exit 1

echo -e "\n    [3] upload to S3 bucket \n"
aws ${AWS_CLI_OPTIONS} s3 sync ./ci ${S3_PATH} --exclude "codebuild/**/*"

echo -e "\n    [4] generate signed urls \n"
PIPELINE_URLS=($(echo ${PIPELINE_TMPL_LIST} | generateSignedUrl))

echo -e "\n    [5] deploy stack of pipeline\n"
PIPELINE_STACK_NAME="pipeline-notification"
PARAMETERS_FILE="/tmp/$$-parameter.json"
PIPELINE_PARAMETERS="[
{\"ParameterKey\":\"SourceCodeRepositoryTmplPath\",\"ParameterValue\":\"${PIPELINE_URLS[1]}\"},
{\"ParameterKey\":\"ArtifactRepositoryTmplPath\",\"ParameterValue\":\"${PIPELINE_URLS[2]}\"},
{\"ParameterKey\":\"UnitTestsProjectTmplPath\",\"ParameterValue\":\"${PIPELINE_URLS[3]}\"},
{\"ParameterKey\":\"PipelineTmplPath\",\"ParameterValue\":\"${PIPELINE_URLS[4]}\"},
{\"ParameterKey\":\"GithubWebhookProjectTmplPath\",\"ParameterValue\":\"${PIPELINE_URLS[5]}\"},
{\"ParameterKey\":\"ChatBotTmplPath\",\"ParameterValue\":\"${PIPELINE_URLS[6]}\"},
{\"ParameterKey\":\"NotificationsTmplPath\",\"ParameterValue\":\"${PIPELINE_URLS[7]}\"},
{\"ParameterKey\":\"SourceCodeRepositoryURL\",\"ParameterValue\":\"${GITHUB_REPOSITORY_URL}\"},
{\"ParameterKey\":\"SlackWorkspaceId\",\"ParameterValue\":\"${SLACK_WORKSPACE_ID}\"},
{\"ParameterKey\":\"SlackChannelId\",\"ParameterValue\":\"${SLACK_CHANNEL_ID}\"}
]"
echo ${PIPELINE_PARAMETERS} > ${PARAMETERS_FILE}

echo -e "\n      pipeline deploy start."
error=$(aws ${AWS_CLI_OPTIONS} cloudformation describe-stacks --stack-name "${PIPELINE_STACK_NAME}" 2>&1 > /dev/null)
if [ $? -ne 0 ]; then
  createStack ${PIPELINE_STACK_NAME} ${PIPELINE_URLS[0]} "file://${PARAMETERS_FILE}"
else
  updateStack ${PIPELINE_STACK_NAME} ${PIPELINE_URLS[0]} "file://${PARAMETERS_FILE}"
fi

rm ${PARAMETERS_FILE}
