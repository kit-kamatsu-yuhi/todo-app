#!/bin/sh
# block-dangerous-commands.sh
# PreToolUse hook: Bash で危険なコマンドの実行をブロックする
#
# POSIX sh 互換 — bash/zsh どちらの環境でも動作する
# shebang (#!/bin/sh) がインタプリタを決定するため、ユーザーのログインシェルに依存しない
#
# Claude Code は stdin に JSON を渡す:
#   {"tool_name": "Bash", "tool_input": {"command": "rm -rf /", ...}}

set -eu

input=$(cat)

# tool_input.command を取得
command_str=$(printf '%s' "$input" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tool_input = data.get('tool_input', {})
print(tool_input.get('command', ''))
" 2>/dev/null || echo "")

if [ -z "$command_str" ]; then
  exit 0
fi

# クォート内の文字列を除外してコマンド部分のみを検査対象にする
# これにより git commit -m "...git push..." のような誤検知を防ぐ
sanitized_str=$(printf '%s' "$command_str" | python3 -c "
import sys, re
s = sys.stdin.read()
# ヒアドキュメント（<<'EOF'...EOF / <<EOF...EOF）を除去
s = re.sub(r\"<<'?(\w+)'?.*?\\1\", ' ', s, flags=re.DOTALL)
# シングルクォート・ダブルクォート内を除去
s = re.sub(r\"'[^']*'\", ' ', s)
s = re.sub(r'\"[^\"]*\"', ' ', s)
print(s)
" 2>/dev/null || printf '%s' "$command_str")

# 危険なコマンドパターンをチェック（POSIX ERE: [[:space:]] を使用）
check_pattern() {
  printf '%s' "$sanitized_str" | grep -qiE -e "$1"
}

if check_pattern 'rm[[:space:]]+-rf[[:space:]]+/$' \
   || check_pattern 'rm[[:space:]]+-rf[[:space:]]+/(usr|etc|var|bin|sbin|lib|boot|dev|proc|sys|opt|home|root)(/|[[:space:]]|$)' \
   || check_pattern 'rm[[:space:]]+-fr[[:space:]]+/$' \
   || check_pattern 'rm[[:space:]]+-fr[[:space:]]+/(usr|etc|var|bin|sbin|lib|boot|dev|proc|sys|opt|home|root)(/|[[:space:]]|$)' \
   || check_pattern 'rm[[:space:]]+-rf[[:space:]]+\*' \
   || check_pattern 'mkfs\.' \
   || check_pattern 'dd[[:space:]]+if=.*of=/dev/' \
   || check_pattern 'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/' \
   || check_pattern 'chown[[:space:]]+-R[[:space:]]+.*[[:space:]]+/' \
   || check_pattern 'git[[:space:]]+push[[:space:]]+.*--force' \
   || check_pattern 'git[[:space:]]+push[[:space:]]+-f' \
   || check_pattern 'DROP[[:space:]]+TABLE' \
   || check_pattern 'DROP[[:space:]]+DATABASE' \
   || check_pattern 'TRUNCATE[[:space:]]+TABLE' \
   || check_pattern 'curl.*\|[[:space:]]*sh' \
   || check_pattern 'curl.*\|[[:space:]]*bash' \
   || check_pattern 'wget.*\|[[:space:]]*sh' \
   || check_pattern 'wget.*\|[[:space:]]*bash' \
   || check_pattern 'terraform[[:space:]]+destroy' \
   || check_pattern 'terraform[[:space:]]+apply[[:space:]]+-auto-approve' \
   || check_pattern 'terraform[[:space:]]+state[[:space:]]+rm' \
   || check_pattern 'terraform[[:space:]]+taint' \
   || check_pattern 'terraform[[:space:]]+import' \
   || check_pattern 'pulumi[[:space:]]+destroy' \
   || check_pattern 'aws[[:space:]]+rds[[:space:]]+delete-db-instance' \
   || check_pattern 'aws[[:space:]]+rds[[:space:]]+delete-db-cluster' \
   || check_pattern 'aws[[:space:]]+rds[[:space:]]+delete-db-snapshot' \
   || check_pattern 'aws[[:space:]]+ec2[[:space:]]+terminate-instances' \
   || check_pattern 'aws[[:space:]]+ecs[[:space:]]+delete-service' \
   || check_pattern 'aws[[:space:]]+ecs[[:space:]]+delete-cluster' \
   || check_pattern 'aws[[:space:]]+lambda[[:space:]]+delete-function' \
   || check_pattern 'aws[[:space:]]+s3[[:space:]]+rb' \
   || check_pattern 'aws[[:space:]]+s3[[:space:]]+rm[[:space:]]+.*--recursive' \
   || check_pattern 'aws[[:space:]]+iam[[:space:]]+delete-user' \
   || check_pattern 'aws[[:space:]]+iam[[:space:]]+delete-role' \
   || check_pattern 'aws[[:space:]]+secretsmanager[[:space:]]+delete-secret' \
   || check_pattern 'aws[[:space:]]+route53[[:space:]]+delete-hosted-zone' \
   || check_pattern 'aws[[:space:]]+apprunner[[:space:]]+delete-service' \
   || check_pattern 'aws[[:space:]]+ecr[[:space:]]+delete-repository' \
   || check_pattern 'gcloud[[:space:]]+projects[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+sql[[:space:]]+instances[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+compute[[:space:]]+instances[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+run[[:space:]]+services[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+container[[:space:]]+clusters[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+functions[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+app[[:space:]]+services[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+storage[[:space:]]+rm' \
   || check_pattern 'gcloud[[:space:]]+storage[[:space:]]+buckets[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+iam[[:space:]]+service-accounts[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+pubsub[[:space:]]+topics[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+pubsub[[:space:]]+subscriptions[[:space:]]+delete' \
   || check_pattern 'gcloud[[:space:]]+firestore[[:space:]]+databases[[:space:]]+delete' \
   || check_pattern 'git[[:space:]]+reset[[:space:]]+--hard' \
   || check_pattern 'git[[:space:]]+clean[[:space:]]+-f' \
   || check_pattern 'rm[[:space:]]+-rf[[:space:]]+(\./?)?\.git([/[:space:]]|$)' \
   || check_pattern 'docker[[:space:]]+system[[:space:]]+prune[[:space:]]+-a[[:space:]]+--volumes' \
   || check_pattern 'kubectl[[:space:]]+delete[[:space:]]+namespace' \
   || check_pattern 'npm[[:space:]]+publish' \
   || check_pattern 'cargo[[:space:]]+publish'; then
  echo "BLOCKED: 危険なコマンドの実行がブロックされました。"
  echo "コマンド: $command_str"
  exit 2
fi

exit 0
