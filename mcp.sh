#initialize
headers=$(curl -s -D - \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"clientInfo":{"name":"manual-client","version":"1.0.0"}}}' \
  http://127.0.0.1:8000/mcp -o /dev/null)

session_id=$(echo "$headers" | grep -i "mcp-session-id"  | awk -F": " '{print $2}' | tr -d '\r\n')

echo "$session_id"
curl -s -X POST  -H "Content-Type: application/json" -H "mcp-session-id: $session_id" -H "Accept: application/json" --data '{"jsonrpc": "2.0", "method": "notifications/initialized"}' http://127.0.0.1:8000/mcp/ && echo "Initialized!"
# list tools
list=$(curl -X POST  -H "Content-Type: application/json"  -H "Accept: application/json" -H "mcp-session-id: $session_id" --data '{ "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}'  http://127.0.0.1:8000/mcp/)
tool_calling=$(echo "$list" | jq '{tools: [ .result.tools[] | { type: "function", function: { name: .name, description: .description, parameters: { type: "object", properties: (.inputSchema.properties), required: (.inputSchema.required)}}}]}')
user_input=$(gum input)
output=$(curl -s http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d "$(jq -n --argjson tools "$tool_calling" --arg content "$user_input" '{model: "gpt-3.5-turbo", tools: $tools.tools, messages:[{role: "user", content: $content}]}')")
reasoning=$(echo "$output" | jq -r '.choices[0].message.reasoning_content')
echo "Reasoning Content:"
echo "$reasoning"
content=$(echo "$output" | jq -r '.choices[0].message.tool_calls // "" ')
echo "Content:"
echo "$content"
tool_calls=$(echo "$output" | jq -r '.choices[0].message.tool_calls // empty')
if [ $? -eq 0 ] && [ -n "$tool_calls" ]; then
    echo "Tool Calls:"
    echo "$tool_calls" | jq -r '.[] | "Tool Name: \(.function.name), Arguments: \(.function.arguments)"'
else
    echo "Tool Calls: "
fi
