#initialize
headers=$(curl -s -D - \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"clientInfo":{"name":"manual-client","version":"1.0.0"}}}' \
  http://127.0.0.1:8000/mcp -o /dev/null)

session_id=$(echo "$headers" | grep -i "mcp-session-id"  | awk -F": " '{print $2}' | tr -d '\r\n')

echo "$session_id"
curl -X POST  -H "Content-Type: application/json" -H "mcp-session-id: $session_id" -H "Accept: application/json" --data '{"jsonrpc": "2.0", "method": "notifications/initialized"}' http://127.0.0.1:8000/mcp/ && echo "Initialized!"
# list tools
list=$(curl -X POST  -H "Content-Type: application/json"  -H "Accept: application/json" -H "mcp-session-id: $session_id" --data '{ "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}'  http://127.0.0.1:8000/mcp/)
tool_calling=$(echo "$list" | jq '{
  tools: [
    .result.tools[] | {
      type: "function",
      function: {
        name: .name,
        description: .description,
        parameters: {
          type: "object",
          properties: (.inputSchema.properties),
          required: (.inputSchema.required)
        }
      }
    }
  ]
}')
jq -n --argjson tools "$tool_calling" '{ model: "gpt-3.5-turbo", tools: $tools.tools, messages:[{role: "user",content: "what time is it now"}]}' 
curl -s http://localhost:8080/v1/chat/completions -H "Content-Type: application/json"  -d "$(jq -n --argjson tools "$tool_calling" '{ model: "gpt-3.5-turbo", tools: $tools.tools, messages:[{role: "user",content: "what time is it now"}]}')"
