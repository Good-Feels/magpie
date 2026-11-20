# Connect Magpie to an AI client

MCP lets an assistant search and read the clips you choose to share. These steps require a Magpie build with an **MCP** tab in Settings. Keep Magpie running while you use the connector.

## Choose what to share

1. Open **Magpie → Settings → MCP** and turn on **Enable MCP sharing**.
2. In Magpie’s history, right-click a text clip and select **Share with AI**. A link icon marks the shared clip.
3. Right-click the clip and select **Stop Sharing with AI** to revoke that clip, or use **Stop Sharing All** in Settings. Deleting a clip or aging it out of history also revokes it. Turning MCP sharing off or quitting Magpie clears the shared selection.

Magpie starts with sharing off. You can share up to 50 clips at a time. Each clip must have a plain-text representation of at most 16 KiB. The tools can search and read that text. The listening socket is private to your macOS user and there is no public network listener. When an AI client reads a clip, its provider may receive the text. Revoking access stops future reads from Magpie. Any text already sent remains subject to the client’s data and retention settings.

## Claude Desktop for macOS

1. Open **Claude Desktop → Settings → Developer → Edit Config**. On macOS, the file is `~/Library/Application Support/Claude/claude_desktop_config.json`.
2. Copy the JSON from **Magpie → Settings → MCP**. It uses your actual Magpie executable path. If your Claude config already contains `mcpServers`, add just the `magpie` entry under it.

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

ChatGPT reaches Magpie through an outbound-only OpenAI Secure MCP Tunnel. You need access to custom MCP servers in your ChatGPT account and the required tunnel permissions in your OpenAI Platform organization. Keep the resulting plugin private to your account because this tunnel connects ChatGPT to your Mac’s shared clips. [OpenAI tunnel permissions and setup](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels#permissions-and-access)

1. In [OpenAI Platform tunnel settings](https://platform.openai.com/settings/organization/tunnels), create a tunnel and associate it with the ChatGPT workspace you will use. Download OpenAI’s [tunnel-client](https://github.com/openai/tunnel-client/releases/latest) for your Mac. Follow the official setup guide to provide the tunnel client's control-plane credential as an environment variable.
2. On the same Mac and under the same macOS account as Magpie, configure the tunnel with your ID and the stdio command shown in **Magpie → Settings → MCP**. For Magpie installed in Applications, use the command below.

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

## Try a shared clip

1. Copy and share a harmless phrase such as `Magpie setup test 842`.
2. Ask your client: “Use Magpie to search my shared clips for ‘setup test 842’ and read the matching clip.”
3. Stop sharing the clip. In a fresh chat, ask the client to search again. The tool should return zero matches. A previous chat can still contain the earlier result.

If a client lists the tools but reports that sharing is unavailable, launch Magpie and check for **Ready** in **Settings → MCP**. Use the executable path from that same build. For ChatGPT, also check that your tunnel is running and associated with the workspace where you added the plugin.
