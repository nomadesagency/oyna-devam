# Turns `claude -p --output-format stream-json` output into human-readable lines (the "stream" resume mode).
def ts: (now | localtime | strftime("%H:%M:%S"));
def clip($n): (tostring | gsub("\\s+"; " ") | if length > $n then .[0:$n] + "…" else . end);
def tooldesc:
  if .name == "Bash" then (.input.description // .input.command)
  elif (.name == "Agent" or .name == "Task") then (.input.description // .input.prompt)
  elif .input.file_path then .input.file_path
  elif .input.pattern then .input.pattern
  else (.input | tostring) end;
if .type == "system" and .subtype == "init" then
  "[\(ts)] ▶ session resumed (\(.session_id[0:8]))"
elif .type == "assistant" then
  (.message.content[]?
   | if .type == "text" then "[\(ts)] 💬 \(.text | clip(400))"
     elif .type == "tool_use" then "[\(ts)] 🔧 \(.name): \(tooldesc | clip(140))"
     else empty end)
elif .type == "user" then
  (.message.content[]? | select(type == "object" and .type == "tool_result") | "          ↳ \(.content | clip(110))")
elif .type == "result" then
  "[\(ts)] ■ turn finished (\(.subtype)) — \((.result // "") | clip(300))"
else empty end
