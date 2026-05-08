#!/usr/bin/env bash
# Claude Code statusline: cwd + model + context usage + session token/cost

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
model_id=$(echo "$input" | jq -r '.model.id // ""')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
used_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
total=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# shorten cwd: replace home dir with ~
home_dir="$USERPROFILE"
if [ -n "$home_dir" ]; then
  cwd="${cwd//$home_dir/~}"
fi

# build progress bar (10 chars)
bar=""
if [ -n "$used_pct" ]; then
  filled=$(printf "%.0f" "$(echo "$used_pct / 10" | bc -l 2>/dev/null || echo 0)")
  [ "$filled" -gt 10 ] 2>/dev/null && filled=10
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  for i in $(seq 1 "$filled" 2>/dev/null); do bar="${bar}█"; done
  for i in $(seq 1 $((10 - filled)) 2>/dev/null); do bar="${bar}░"; done
fi

# format token count (e.g. 12k)
fmt_tokens=""
if [ -n "$used_tokens" ] && [ -n "$total" ]; then
  used_k=$(echo "$used_tokens" | awk '{printf "%.0fk", $1/1000}')
  total_k=$(echo "$total" | awk '{printf "%.0fk", $1/1000}')
  fmt_tokens="${used_k}/${total_k}"
fi

# session cumulative token usage + cost from transcript jsonl
session_info=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  session_info=$(MODEL_ID="$model_id" awk '
  BEGIN {
    in_tok=0; out_tok=0; cache_read=0; cache_write=0

    # model-based pricing table (per 1M tokens)
    mid = ENVIRON["MODEL_ID"]
    fallback = 0

    # strip trailing variant suffix like [1m], -20251001, etc. for matching
    # opus-4 family
    if (mid ~ /claude-opus-4/) {
      in_price  = 15.00
      out_price = 75.00
      cr_price  = 1.50
      cw_price  = 18.75
    }
    # haiku-4 family
    else if (mid ~ /claude-haiku-4/) {
      in_price  = 1.00
      out_price = 5.00
      cr_price  = 0.10
      cw_price  = 1.25
    }
    # sonnet-4 family (including 4-5, 4-6, etc.)
    else if (mid ~ /claude-sonnet-4/) {
      in_price  = 3.00
      out_price = 15.00
      cr_price  = 0.30
      cw_price  = 3.75
    }
    # fallback: sonnet pricing + flag with ?
    else {
      in_price  = 3.00
      out_price = 15.00
      cr_price  = 0.30
      cw_price  = 3.75
      fallback  = 1
    }
  }
  {
    if (match($0, /"input_tokens":([0-9]+)/, a))    in_tok   += a[1]
    if (match($0, /"output_tokens":([0-9]+)/, a))   out_tok  += a[1]
    if (match($0, /"cache_read_input_tokens":([0-9]+)/, a))  cache_read  += a[1]
    if (match($0, /"cache_creation_input_tokens":([0-9]+)/, a)) cache_write += a[1]
  }
  END {
    total = in_tok + out_tok
    cost = (in_tok * in_price + out_tok * out_price + cache_read * cr_price + cache_write * cw_price) / 1000000
    # format totals
    if (total >= 1000000)      tot_str = sprintf("%.1fM", total/1000000)
    else if (total >= 1000)    tot_str = sprintf("%.0fk", total/1000)
    else                       tot_str = total
    cost_str = sprintf("$%.2f", cost)
    if (fallback) cost_str = cost_str "?"
    printf "%s/%s", tot_str, cost_str
  }
  ' "$transcript" 2>/dev/null)
fi

# assemble parts
parts=()
[ -n "$cwd" ]   && parts+=("$cwd")
[ -n "$model" ] && parts+=("[$model]")

if [ -n "$used_pct" ]; then
  pct_str=$(printf "%.0f%%" "$used_pct")
  ctx_str="ctx:${bar}${pct_str}"
  [ -n "$fmt_tokens" ] && ctx_str="${ctx_str}(${fmt_tokens})"
  parts+=("$ctx_str")
fi

[ -n "$session_info" ] && parts+=("tok:${session_info}")

printf "%s" "$(IFS=' | '; echo "${parts[*]}")"
