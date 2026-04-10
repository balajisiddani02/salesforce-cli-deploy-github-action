#!/usr/bin/env bash
set -e
if [ "$MERGE_DEPLOY" = "true" ] && [ -z "$SOURCE_BRANCH" ]; then
  echo "ERROR: merge_deploy is true but source_branch is not provided"
  exit 1
fi

if [ "$CODE_SCAN" = "true" ] && [ -z "$SCAN_RULES_PATH" ]; then
  echo "ERROR: code_scan is true but scan_rules_path is not provided"
  exit 1
fi

if [ "$DELTA_DEPLOY" != "true" ] && [ "$OWN_DEPLOY" != "true" ]; then
  echo "ERROR: No deployment option selected"
  exit 1
fi

npm install -g @salesforce/cli@"$CLI_VERSION"

sf plugins install sfdx-git-delta
sf plugins install @salesforce/sfdx-scanner
sf plugins install apextestlist

AUTH_FILE=$(mktemp)
echo "$SFDX_AUTH_URL" > "$AUTH_FILE"

sf org login sfdx-url --sfdx-url-file "$AUTH_FILE" --alias "$ORG_ALIAS" --set-default

rm -f "$AUTH_FILE"

if [ "$MERGE_DEPLOY" = "true" ]; then
  git fetch origin
  git merge "origin/$SOURCE_BRANCH" --no-ff --no-edit
fi

mkdir -p deltaChanges

sf sgd:source:delta \
  --from "$FROM_REF" \
  --to "$TO_REF" \
  --output deltaChanges \
  --generate-delta
``

if [ "$CODE_SCAN" = "true" ]; then
  sf scanner run \
    --target deltaChanges \
    --engine pmd \
    --pmd-config "$SCAN_RULES_PATH" \
    --severity-threshold "$SEVERITY_THRESHOLD"
fi

TESTS=""

if [ "$DELTA_DEPLOY" = "true" ] && [ "$RUN_SPECIFIED_TESTS" = "true" ]; then
  sf apextests list \
    -x deltaChanges/package/package.xml \
    -m \
    --json > selected-tests.json

  TESTS=$(jq -r '.result | join(",")' selected-tests.json)
fi

if [ "$DELTA_DEPLOY" = "true" ]; then
  if [ "$RUN_SPECIFIED_TESTS" = "true" ] && [ -n "$TESTS" ]; then
    sf project deploy start \
      --manifest deltaChanges/package/package.xml \
      --target-org "$ORG_ALIAS" \
      --test-level RunSpecifiedTests \
      --tests "$TESTS"
  else
    sf project deploy start \
      --manifest deltaChanges/package/package.xml \
      --target-org "$ORG_ALIAS" \
      --test-level NoTestRun
  fi
fi

if [ "$OWN_DEPLOY" = "true" ]; then
  eval "$CUSTOM_DEPLOY_CMD"
fi
