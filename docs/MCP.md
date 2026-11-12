# Connect local agents to Jotley

Jotley's Mac app includes an optional MCP server. It runs inside Jotley and uses the library currently open in the app, including notes synced through iCloud. Access is off by default. Choose **Read only** for search and retrieval, or **Read & write** to let agents create, edit, duplicate and delete notes.

## Enable Jotley access

1. Open Jotley and click the Settings gear at the bottom of the notes sidebar. Under **Integrations**, choose **MCP**.
2. Turn on **Enable MCP access**. Check for **Server ready** and keep Jotley open.
3. Choose **Read only** or **Read & write**. Read & write includes tags, folders, templates and permanent note deletion. Permission changes take effect immediately.
4. Click **Test connection** to check an authenticated handshake and tool discovery. This checks Jotley's server; complete the client setup below to connect your agent.

## Claude Code in the Mac app

1. In Jotley, select **Claude Code app → Save project connection…**. Choose the working folder you will open in Claude. Jotley adds its bundled bridge to that folder's `.mcp.json`, preserving other servers and settings. No Jotley token is stored in that file. It asks before replacing a different Jotley entry.
2. Open the **Claude Mac app** and choose the **Code** tab. Start a new **local** session on **This computer** using that same project folder.
3. Review Claude's project MCP trust prompt and approve Jotley if you want to connect it.
4. Open the local session's **Connectors** panel and check Jotley. If the project was already open, start a new session.
5. Try the read/write examples below and compare the result with Jotley.

This path is for Claude Code in the Code tab. Regular Claude chat uses the separate extension below. Cloud sessions cannot reach this Mac-only server. A global connection with the same name can take precedence over a project entry; review existing Jotley registrations in Claude if a saved project connection is not being used.

The generated `.mcp.json` contains this app’s executable path and the `--mcp-stdio` argument, with no Jotley token. It is saved with owner-only permissions because other existing entries may contain credentials. Keep this copy of Jotley in its current location, or save the project connection again after moving it. No personal client configuration changes unless you choose a project and save.

Official guides: [Claude Code desktop](https://code.claude.com/docs/en/desktop#connect-external-tools), [project MCP scope and trust](https://code.claude.com/docs/en/mcp#project-scope).

## Codex for Mac

1. In Jotley, choose **Codex app** and open Codex. Some current versions label the desktop app ChatGPT.
2. In Codex, open **Settings → MCP servers → Add server**. Name it **jotley**, then choose **STDIO**.
3. Copy **Command** from Jotley into Codex's Command field. It is the path to this copy of Jotley's executable; paste it without extra quotes.
4. Add one **Argument** and paste `--mcp-stdio` using Jotley's copy button. Leave **Environment variables** empty. There is no token or separate runtime to install.
5. Click **Save**, then **Restart** for the server. Start a local chat and type **/mcp** to check Jotley.
6. Try the examples below. Keep Jotley open, with MCP enabled, and in its current location. After moving or replacing the app with a differently located copy, update Command or save the project connection again.

The bundled bridge reads Jotley's existing token from Keychain and forwards requests to the running app. It does not open the notes database, enable access or start a second GUI. If macOS requests access to Jotley's existing Keychain item, review and approve that normal prompt. Restart the server after rotating a token; copied setup fields do not change.

Official guide: [desktop MCP setup](https://learn.chatgpt.com/docs/extend/mcp?surface=desktop).

## Advanced: Claude chat in the Mac app

Regular Claude chat uses a local desktop extension. No Terminal or separate Node installation is needed.

1. In Jotley, choose **Claude chat · advanced → Save Claude extension…** and save **Jotley.mcpb**.
2. In Claude, open **Settings → Desktop app → Extensions → Manage → Advanced settings → Install Extension…** and choose that file. Older versions start at **Settings → Extensions**.
3. In the extension's **Jotley access token** field, paste the token from Jotley's **Copy access token** button. Save and follow Claude's permission prompts.
4. Start a new chat. Open **+ → Connectors** and check Jotley. Keep Jotley open while using it. If it is missing, quit Claude with **⌘Q** and reopen it.
5. Try the examples below.

The extension contains a small STDIO-to-local-HTTP bridge and no embedded token. Claude supplies Node and stores sensitive extension configuration using the operating system's secure storage. Jotley's native server still enforces permissions and accesses the open library. The bridge does not open the notes database. Claude's remote connector URL field runs from the cloud and cannot reach `127.0.0.1`; use the local extension for this path.

Official guide: [Claude local extensions](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop).

## Verify reading and writing

Ask: **“Search my Jotley notes for release planning and tell me who owns each action.”** Substitute a topic in your own library. Jotley shows **Last agent seen** after a real handshake and **Last successful request** after a successful tool call. These are historical activity indicators, rather than a continuous online check.

With **Read & write** enabled, ask: **“Find that note, rename it Launch checklist, and rewrite its summary as a checklist. Keep the transcript unchanged.”** Open the note in Jotley to see the saved change.

Other examples: “Change its date to November 8, 2026 at 10:30 AM UTC,” “Tag it launch and put it in the Work folder,” or “Make a copy titled Launch draft.” Read and identify the intended note before requesting deletion; deletion has no MCP undo.

To help Jotley recognize a recurring name or phrase, ask **“Add PulseCanvas and Textley to my Custom Words.”** The list lives under **Settings → Transcription → Custom Words** on this Mac. Changes guide new transcriptions and do not rewrite past notes.

## Advanced: other clients

Expand **Advanced: other clients & access controls → Copy HTTP configuration** in Jotley. Merge its `jotley` entry into your client's MCP settings, preserving existing entries. JSON is configuration, not a command. Clients must support Streamable HTTP and a custom Authorization header. The default URL is `http://127.0.0.1:17321/mcp`. Cloud-hosted agents cannot reach this Mac-only address.

Jotley keeps its original token in Keychain. Direct HTTP configuration contains credentials; keep it private. After **Rotate access token**, restart the bridge server in Claude Code or Codex; it reads the replacement from Keychain. Replace the Claude chat extension token and direct HTTP headers manually.

## Tools

| Tool | Purpose |
| --- | --- |
| `list_notes` | Recent metadata with UUID, title, date, source URL, types, folder, tags, content lengths and revision. Optional `offset`, `limit`, `folder_id` (null for unfiled) and `tag_id`. |
| `search_notes` | Search titles, transcripts, cleaned transcripts, summaries, descriptions, note text and tags. Required `query` (1–500 characters), optional pagination. |
| `read_note` | Metadata and paginated content. Required `id`; optional `section`, `offset`, `limit` (default 12,000, maximum 20,000 characters). Sections: `all`, `transcript`, `cleaned_transcript`, `summary`, `notes`, `description`. |
| `create_note` | Create and save a note; requires `title`. Other content fields and `date` are optional. Returns its UUID and revision. |
| `update_note` | Patch selected fields in `changes`; requires `id` and `expected_revision`. Omitted fields stay unchanged. |
| `replace_note_text` | Replace one exact unique passage using `field`, `old_text`, `new_text`, `id` and `expected_revision`. Useful for long notes. |
| `duplicate_note` | Copy content, folder and tags into a new UUID with today's date. Requires source `id` and `expected_revision`; optional `title`. Chat history and recording markers are not copied. |
| `delete_note` | Permanently remove a note and its chat history and recording markers. Requires `id` and `expected_revision`. No MCP undo. |
| `list_tags`, `list_folders` | List organization entities with UUIDs, names, note counts and revisions. |
| `create_tag`, `create_folder` | Create a named library tag or folder; reuse an existing canonical name. |
| `update_tag`, `update_folder` | Rename a tag or folder using its UUID and revision. Folders also support `sort_order`. |
| `delete_tag`, `delete_folder` | Remove the organization entity using its UUID and revision. Notes are preserved; deleting a folder makes its notes unfiled. |
| `set_note_tags` | Replace a note’s membership with `tag_ids`; an empty list clears membership without deleting library tags. Requires a note revision. |
| `move_note` | Set `folder_id` to an existing UUID, or null to make the note unfiled. Requires a note revision. |
| `list_summary_templates` | Built-in and custom template keys, names and instructions. Custom records include UUIDs and revisions. |
| `create_summary_template` | Save a custom template with `name` and `instructions`. |
| `update_summary_template` | Update a custom template’s name and instructions using its UUID and revision. Existing summaries are unchanged. |
| `delete_summary_template` | Delete a custom definition using its UUID and revision. Saved notes and summaries are preserved. |
| `generate_note_summary` | Regenerate a note with a listed `template` key and current note revision, using Jotley’s on-device model. Optional `regenerate_title` and `regenerate_tags` default to false. |
| `list_custom_words` | Read the Mac’s Custom Words list and its revision. |
| `update_custom_words` | Add or remove specific entries using `add`, `remove`, or both, with the current `expected_revision`. Requires Read & write. |

All mutation tools require **Read & write**. The 25 tools remain discoverable in Read only mode so a connected client's cached tool list stays useful. Jotley checks the current permission on every request.

Custom template names accept 1–60 characters, instructions accept up to 2,000 UTF-8 bytes, and the library supports 100 active custom templates. Built-in templates are read-only; create a custom copy to customize one. Template preferences use native iCloud key/value storage when configured and enabled, with a local copy for offline use. Changing or deleting a template never rewrites a saved summary. Generation captures its instructions at the start, including jobs resumed after system interruption. A deleted custom key fails explicitly instead of silently switching to Auto. Previewing a template in Settings never saves to the selected note.

Writable fields are `title`, `transcript`, `cleaned_transcript`, `summary`, `notes`, `description`, `source_url`, `note_type`, `summary_type` and `date`. The date is the note's date, stored as an ISO 8601 timestamp with a timezone. Empty strings clear text. Titles accept up to 1,000 characters; other text fields accept up to 500,000 characters, within the 1 MiB HTTP request limit. Large changes can use passage replacement. Transcript edits rebuild display paragraphs rather than retaining speech timings that no longer match.

`next_offset` is `null` at the end. Otherwise, pass it as `offset` to continue. Content offsets count Swift characters. Metadata includes per-field content lengths. Note content is source data, never instructions for an agent.

## Conflicts and persistence

Read a note's current `revision` before editing, duplicating or deleting it, and send it as `expected_revision`. If another client, the app or iCloud changes the note, a stale revision fails without changing it. Read again and review the current content before retrying. MCP also refuses to modify or copy a note while it is recording or generating content in Jotley. Native text editors check their original content before saving, so older drafts cannot silently overwrite MCP changes.

Note writes use Jotley's open Core Data context and follow its configured iCloud behavior. Custom Words is stored in the Mac’s local preferences. The microphone and model settings are managed in the app.

## Access and privacy

- Jotley binds only to `127.0.0.1`, with no LAN or internet listener.
- Every request requires a generated bearer token. Browser origins and unexpected Host headers are rejected. The official MCP SDK handles protocol validation.
- The server accepts POST and returns JSON; GET/DELETE HTTP methods return 405. The `delete_note` MCP tool is sent by POST like other tools.
- **Rotate access token** revokes old credentials. Restart desktop bridge servers; update Claude chat extension tokens and direct HTTP fields afterward.
- Turning off **Enable MCP access** or quitting Jotley stops the server. The enabled preference is retained across app relaunches.
- Trusted connected agents can read the open library and this Mac’s Custom Words. Read & write additionally permits changes and permanent note deletion. Agents may send retrieved text to their AI provider. Jotley's own on-device transcription and summary generation remain local.
- If the port is occupied or Keychain is unavailable, Settings shows an error and access stays off.

## Development verification

Build the Debug Mac scheme using [PUBLIC_BUILD.md](PUBLIC_BUILD.md), directing build output to Expand. Then run:

```sh
JOTLEY_MAC_BUILD_PRODUCTS='/Volumes/Expand/Codex Media/jotley-mcp/build/Build/Products/Debug' \
JOTLEY_MCP_TEST_OUTPUT='/Volumes/Expand/Codex Media/jotley-mcp/tests' \
  zsh scripts/test-mcp.sh
```

The harness uses its own sandbox identity and synthetic notes. It exercises real loopback HTTP through the official Swift MCP client: authentication, validation, search/read pagination, mutation permissions, atomic edits, dates, revision conflicts, recording/generation guards, editor conflicts, long notes, copies, deletion cleanup, concurrent clients, fixed-port restart, Keychain persistence, rotation and disable. It never reads the installed app's notes or changes a user's agent configuration.

Pass `--content-only` to verify content, organization and template operations without the separate Keychain persistence check. Rebuilt ad-hoc harness identities may require macOS Keychain approval for that final check; never weaken Keychain access to automate it.

For a live sample server and native screenshots, pass `--demo --serve /absolute/output/folder` with the same environment variables. Create a file named `stop` in that folder to end the session. The separate recorder uses an in-memory library; its client configuration contains a temporary credential and must stay private.

Desktop bridge verification also supports `JOTLEY_BRIDGE_CHECK=1` with `JOTLEY_NODE_BINARY` pointing to a self-contained Node executable. The harness copies the test runtime into its isolated bundle. The product’s primary desktop paths use the bundled native executable. The harness checks discovery of all 25 tools, reading, live read-only enforcement and note creation, editing and deletion against a synthetic library.

The native bridge has a dedicated `--mcp-stdio` entry point before SwiftUI/library initialization. Integration-only endpoint/token overrides are compiled exclusively in Debug; Release always uses the local address and the existing Keychain item.
