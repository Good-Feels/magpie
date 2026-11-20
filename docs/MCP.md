# Connect Magpie to an AI client

MCP lets connected assistants search and read all clips in your Magpie history, including newly copied clips and clips older than the ones visible in the history window. Keep Magpie running while you use the connector.

## Allow access to clipboard history

Open **Magpie → Settings → MCP** and turn on **Allow access to clipboard history**. Access starts off and Magpie remembers your choice across launches. Turn it off to block future reads. Deleting a clip or aging it out of history also removes it from MCP results.

Search returns up to 20 previews per page. The tools return plain text from text and rich-text clips, images sized for the response, and saved paths from file clips. Long text can be read across multiple requests. File clips store references to files. The connector reads those saved references.

The local connection is private to your macOS user. When an assistant reads a clip, its provider may receive that clip. Previously retrieved clips remain subject to the client’s data and retention settings. [Setup guide for Magpie 1.0.19](https://github.com/Good-Feels/magpie/blob/v1.0.19/docs/MCP.md)

## Claude Desktop for macOS

In **Magpie → Settings → MCP**, click **Connect to Claude**. Magpie opens a desktop extension in Claude. Approve the installation, then start a new Claude chat and try the sample below. If you move Magpie to a different folder, reconnect from Magpie using the new location.

### Manual Claude Desktop setup

1. Open **Claude Desktop → Settings → Developer → Edit Config**. On macOS, the file is `~/Library/Application Support/Claude/claude_desktop_config.json`.
2. Add the JSON below. If your Claude config already contains `mcpServers`, add just the `magpie` entry under it. If Magpie is installed somewhere else, use its actual executable path.

   ```json
   {
     "mcpServers": {
       "magpie": {
         "command": "/Applications/Magpie.app/Contents/MacOS/Magpie",
         "args": ["--mcp-stdio"]
       }
     }
   }
   ```

3. Quit Claude Desktop with **Command-Q** and reopen it. Start a new Claude chat and try the sample below. To check the local server status, use **Settings → Desktop app → Extensions → Manage** or **Settings → Developer** in the older layout. Managed settings may restrict local MCP servers.

[Claude Desktop MCP help](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop) · [MCP config guide](https://modelcontextprotocol.io/docs/develop/connect-local-servers)

Claude’s web and Cowork remote connectors require an Anthropic-reachable HTTPS MCP server. Magpie’s Claude integration uses the local Claude Desktop client. [Claude remote connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)

## ChatGPT via Secure MCP Tunnel

ChatGPT reaches Magpie through an outbound-only OpenAI Secure MCP Tunnel. You need access to custom MCP servers in your ChatGPT account and the required tunnel permissions in your OpenAI Platform organization. Keep the resulting plugin private to your account because this tunnel connects ChatGPT to your Magpie clipboard history. [OpenAI tunnel permissions and setup](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels#permissions-and-access)

In **Magpie → Settings → MCP**, click **Connect to ChatGPT** and copy the setup prompt. Paste it into a local Codex chat on the same Mac. Codex guides you through setting up the private tunnel, approving the ChatGPT plugin, and testing a clip.

### Manual ChatGPT setup

1. In [OpenAI Platform tunnel settings](https://platform.openai.com/settings/organization/tunnels), create a tunnel and associate it with the ChatGPT workspace you will use. Download OpenAI’s [tunnel-client](https://github.com/openai/tunnel-client/releases/latest) for your Mac. Follow the official setup guide to provide the tunnel client's control-plane credential as an environment variable.
2. On the same Mac and under the same macOS account as Magpie, configure the tunnel with your ID. For Magpie installed in Applications, use the command below. Update the executable path if Magpie is installed elsewhere.

   ```sh
   tunnel-client init \
     --sample sample_mcp_stdio_local \
     --profile magpie \
     --tunnel-id YOUR_TUNNEL_ID \
     --mcp-command '/Applications/Magpie.app/Contents/MacOS/Magpie --mcp-stdio'

   tunnel-client doctor --profile magpie --explain
   tunnel-client run --profile magpie
   ```

3. While the tunnel client is running, go to [ChatGPT Plugins](https://chatgpt.com/plugins). Use **+ → Add custom MCP server**, name it **Magpie**, select **Tunnel** as the connection, and choose your tunnel. Choose **No authentication** for the MCP server itself. The private tunnel controls OpenAI access and the local Magpie process runs under your macOS account.
4. Choose **Create as a plugin**, then **Connect Magpie**. In the **Personal** tab, open Magpie and click **Try in chat**. This starts a new chat with **@Magpie** selected. Keep the tunnel client and Magpie running while using it.

[OpenAI custom MCP instructions](https://developers.openai.com/api/docs/guides/custom-mcp-server) · [Secure MCP Tunnel guide](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)

## Claude Code and Codex

Run either command on the Mac running Magpie. If Magpie is elsewhere, replace the executable path with the one shown in Settings.

```sh
claude mcp add --transport stdio --scope user magpie -- /Applications/Magpie.app/Contents/MacOS/Magpie --mcp-stdio
codex mcp add magpie -- /Applications/Magpie.app/Contents/MacOS/Magpie --mcp-stdio
```

Open a new local session and use `/mcp` to check the connection. Other local stdio MCP clients can use the same executable and argument.

[Claude Code MCP documentation](https://code.claude.com/docs/en/mcp) · [Codex MCP documentation](https://developers.openai.com/codex/mcp)

## Try a sample clip

1. With history access enabled, copy a harmless phrase such as `Magpie setup test 842`.
2. Ask your client “Use Magpie to search for ‘setup test 842’ and read the matching clip.”
3. Delete the sample from Magpie. In a fresh chat, ask the client to search again. The tool should return zero matches. You can also turn off history access and confirm the client reports access is disabled.

If a client reports history access is unavailable, launch Magpie and check for **Ready** in **Settings → MCP**. Use the executable path from that same build. For ChatGPT, also check that your tunnel is running and associated with the workspace where you added the plugin.
