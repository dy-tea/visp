module main

import gui
import time
import strings
import net.urllib

// ---------------------------------------------------------------------------
// Scroll id for the messages pane
// ---------------------------------------------------------------------------

const id_scroll_messages = u32(20)

// ---------------------------------------------------------------------------
// Top-level messages panel (header + message list + compose box)
// ---------------------------------------------------------------------------

fn view_messages_panel(window &gui.Window) gui.View {
	app := window.state[App]()

	return gui.column(
		sizing:      gui.fill_fill
		spacing:     0
		padding:     gui.padding_none
		color:       gui.theme().color_background
		content:     [
			messages_header(app),
			messages_header_divider(),
			messages_body(window),
			compose_area(window),
		]
	)
}

// ---------------------------------------------------------------------------
// Header bar
// ---------------------------------------------------------------------------

fn messages_header(app &App) gui.View {
	title  := active_title(app)
	subtitle := active_subtitle(app)

	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(12, 16, 12, 16)
		spacing:     10
		color:       gui.theme().color_panel
		size_border: 0
		v_align:     .middle
		content:     [
			gui.column(
				sizing:  gui.fill_fit
				spacing: 2
				padding: gui.padding_none
				content: [
					gui.text(
						text:       title
						text_style: gui.theme().b3
					),
					if subtitle.len > 0 {
						gui.text(
							text:       subtitle
							text_style: gui.TextStyle{
								...gui.theme().n5
								color: gui.theme().color_active
							}
						)
					} else {
						empty_spacer()
					},
				]
			),
			// Refresh button
			gui.button(
				padding:     gui.padding(4, 6, 4, 6)
				size_border: 0
				radius:      gui.theme().radius_small
				color:       gui.color_transparent
				color_hover: gui.rgba(128, 128, 128, 40)
				tooltip:     &gui.TooltipCfg{ id: 'tt-refresh', content: [gui.text(text: 'Refresh')] }
				content:     [
					gui.text(
						text:       gui.icon_sync
						text_style: gui.theme().icon4
					),
				]
				on_click: fn (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
					app := w.state[App]()
					conv := app.active_conv or { return }
					if conv.kind == .stream {
						action_open_topic(conv.stream_id, conv.stream_name, conv.topic, mut w)
					}
				}
			),
		]
	)
}

fn messages_header_divider() gui.View {
	return gui.rectangle(
		sizing:      gui.fill_fixed
		height:      1
		color:       gui.theme().color_border
		size_border: 0
	)
}

fn active_title(app &App) string {
	conv := app.active_conv or { return 'Visp' }
	return match conv.kind {
		.stream { '#${conv.stream_name}' }
		.direct { conv.dm_name }
	}
}

fn active_subtitle(app &App) string {
	conv := app.active_conv or { return '' }
	return match conv.kind {
		.stream { conv.topic }
		.direct { conv.dm_email }
	}
}

// ---------------------------------------------------------------------------
// Message list
// ---------------------------------------------------------------------------

fn messages_body(window &gui.Window) gui.View {
	app := window.state[App]()

	// No conversation selected
	if _ := app.active_conv {
		// fall through
	} else {
		return gui.column(
			sizing:  gui.fill_fill
			h_align: .center
			v_align: .middle
			content: [
				gui.column(
					spacing: 12
					h_align: .center
					content: [
						gui.text(
							text:       gui.icon_comment
							text_style: gui.TextStyle{
								...gui.theme().icon1
								color: gui.theme().color_border
							}
						),
						gui.text(
							text:       'Select a channel and topic to start reading'
							text_style: gui.TextStyle{
								...gui.theme().n3
								color: gui.theme().color_active
							}
						),
					]
				),
			]
		)
	}

	// Loading spinner
	if app.messages_loading {
		return gui.column(
			sizing:  gui.fill_fill
			h_align: .center
			v_align: .middle
			content: [
				gui.row(
					spacing: 10
					padding: gui.padding_none
					color:   gui.color_transparent
					size_border: 0
					v_align: .middle
					content: [
						gui.text(
							text:       gui.icon_sync
							text_style: gui.theme().icon3
						),
						gui.text(
							text:       'Loading messages…'
							text_style: gui.theme().n3
						),
					]
				),
			]
		)
	}

	// Error state
	if app.messages_error.len > 0 {
		return gui.column(
			sizing:  gui.fill_fill
			h_align: .center
			v_align: .middle
			padding: gui.padding(16, 24, 16, 24)
			content: [
				gui.text(
					text:       app.messages_error
					mode:       .wrap
					text_style: gui.TextStyle{
						...gui.theme().n3
						color: gui.rgb(220, 80, 80)
					}
				),
			]
		)
	}

	msgs := app.all_messages()

	if msgs.len == 0 {
		return gui.column(
			sizing:  gui.fill_fill
			h_align: .center
			v_align: .middle
			content: [
				gui.text(
					text:       'No messages yet. Be the first to write something!'
					text_style: gui.TextStyle{
						...gui.theme().n3
						color: gui.theme().color_active
					}
				),
			]
		)
	}

	// Build message bubbles, grouping consecutive messages from same sender
	mut items := []gui.View{}
	mut prev_sender_id := -1
	mut prev_date := ''

	for i, msg in msgs {
		msg_date := format_date(msg.timestamp)

		// Date separator
		if msg_date != prev_date {
			items << date_separator(msg_date)
			prev_date = msg_date
			prev_sender_id = -1
		}

		is_me := msg.sender_email == app.me.email
		is_continued := msg.sender_id == prev_sender_id && i > 0

		items << message_bubble(msg, is_me, is_continued, window)
		prev_sender_id = msg.sender_id
	}

	return gui.column(
		sizing:          gui.fill_fill
		spacing:         0
		padding:         gui.padding(8, 0, 8, 0)
		id_scroll:       id_scroll_messages
		id_focus:        id_focus_messages
		scrollbar_cfg_y: &gui.ScrollbarCfg{
			overflow: .auto
		}
		content: items
	)
}

// ---------------------------------------------------------------------------
// Date separator
// ---------------------------------------------------------------------------

fn date_separator(label string) gui.View {
	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(8, 16, 8, 16)
		spacing:     10
		color:       gui.color_transparent
		size_border: 0
		h_align:     .center
		v_align:     .middle
		content:     [
			gui.rectangle(
				sizing:      gui.fill_fixed
				height:      1
				color:       gui.theme().color_border
				size_border: 0
			),
			gui.text(
				text:       label
				text_style: gui.TextStyle{
					...gui.theme().n5
					color: gui.theme().color_active
				}
			),
			gui.rectangle(
				sizing:      gui.fill_fixed
				height:      1
				color:       gui.theme().color_border
				size_border: 0
			),
		]
	)
}

// ---------------------------------------------------------------------------
// Single message bubble
// ---------------------------------------------------------------------------

fn message_bubble(msg ZulipMessage, is_me bool, is_continued bool, window &gui.Window) gui.View {
	top_pad    := if is_continued { 2 } else { 10 }
	avatar_url := msg.avatar_url

	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(top_pad, 16, 2, 16)
		spacing:     10
		color:       gui.color_transparent
		size_border: 0
		v_align:     .top
		content:     [
			// Avatar column (fixed 36px wide, hidden for continued messages)
			gui.column(
				width:   36
				sizing:  gui.fixed_fit
				padding: gui.padding_none
				spacing: 0
				content: [
					if !is_continued {
						sender_avatar(avatar_url, msg.sender_full_name)
					} else {
						empty_avatar_spacer()
					},
				]
			),
			// Body column
			gui.column(
				sizing:  gui.fill_fit
				spacing: 2
				padding: gui.padding_none
				content: [
					if !is_continued {
						message_header_row(msg, is_me)
					} else {
						empty_spacer()
					},
					message_content_view(msg, window),
					reactions_row(msg, window),
				]
			),
		]
	)
}

// ---------------------------------------------------------------------------
// Sender avatar
// ---------------------------------------------------------------------------

fn sender_avatar(avatar_url string, full_name string) gui.View {
	return gui.column(
		clip:        true
		width:       36
		height:      36
		sizing:      gui.fixed_fixed
		radius:      18
		color:       gui.Color{ r: 80, g: 90, b: 120, a: 255 }
		h_align:     .center
		v_align:     .middle
		size_border: 0
		padding:     gui.padding_none
		content:     [
			if avatar_url.len > 0 {
				// fill_fill makes the image stretch to fill the 36×36 clip
				// container so it is centered and not anchored top-left.
				gui.image(
					src:    avatar_url
					width:  36
					height: 36
					sizing: gui.fill_fill
				)
			} else {
				gui.text(
					text:       initials(full_name)
					text_style: gui.TextStyle{
						...gui.theme().b5
						color: gui.white
					}
				)
			},
		]
	)
}

fn empty_avatar_spacer() gui.View {
	return gui.rectangle(
		width:       36
		height:      1
		sizing:      gui.fixed_fixed
		color:       gui.color_transparent
		size_border: 0
	)
}

// ---------------------------------------------------------------------------
// Message header (sender name + timestamp)
// ---------------------------------------------------------------------------

fn message_header_row(msg ZulipMessage, is_me bool) gui.View {
	name_style := if is_me {
		gui.TextStyle{
			...gui.theme().b4
			color: gui.Color{ r: 100, g: 160, b: 240, a: 255 }
		}
	} else {
		gui.theme().b4
	}

	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding_none
		spacing:     8
		color:       gui.color_transparent
		size_border: 0
		v_align:     .middle
		content:     [
			gui.text(
				text:       msg.sender_full_name
				text_style: name_style
			),
			gui.text(
				text:       format_time(msg.timestamp)
				text_style: gui.TextStyle{
					...gui.theme().n5
					color: gui.theme().color_active
				}
			),
		]
	)
}

// ---------------------------------------------------------------------------
// Message content — rendered as markdown
// ---------------------------------------------------------------------------

fn message_content_view(msg ZulipMessage, window &gui.Window) gui.View {
	raw := msg.content.trim_space()
	if raw.len == 0 {
		return empty_spacer()
	}

	// Pending (optimistic) messages shown in a lighter style
	is_pending := msg.id < 0
	if is_pending {
		return gui.text(
			text:       raw
			mode:       .wrap
			text_style: gui.TextStyle{
				...gui.theme().n4
				color: gui.theme().color_active
			}
		)
	}

	// Normalise content for the Markdown renderer
	content := prepare_message_content(raw, msg.content_type)

	md_style := gui.MarkdownStyle{
		code_block_bg: gui.rgba(0, 0, 0, 60)
	}

	return window.markdown(
		source:  content
		style:   md_style
		mode:    .wrap
		padding: gui.padding_none
	)
}

// prepare_message_content normalises raw Zulip message text for the Markdown
// renderer:
//   1. Normalises line endings (\r\n → \n).
//   2. If the server returned HTML despite apply_markdown=false (older
//      servers or special message types), strips the HTML tags so the
//      renderer receives plain text instead of raw HTML entities.
//   3. Converts Zulip's ```quote … ``` fenced blocks into standard `>`
//      blockquote syntax so they render as nested quotes.
//   4. Converts Zulip image file links [name.ext](url) to markdown image
//      embeds ![name.ext](url) so they are rendered inline.
fn prepare_message_content(content string, content_type string) string {
	// Normalise CRLF → LF
	mut s := content.replace('\r\n', '\n').replace('\r', '\n')

	// Detect HTML content: either explicit content_type or heuristic
	is_html := content_type == 'text/html' || (s.starts_with('<') && s.contains('<p>'))
	if is_html {
		s = strip_html_tags(s)
	}

	// Convert Zulip ```quote … ``` blocks to Markdown blockquotes.
	// These blocks can be nested, so we process them iteratively until
	// no more substitutions can be made.
	s = convert_zulip_quote_blocks(s)

	// Convert plain file links whose names look like images into markdown
	// image embeds so the renderer displays them inline.
	// Zulip sends  [image.png](/user_uploads/…)  with apply_markdown=false;
	// we want  ![image.png](/user_uploads/…)  so the markdown parser treats
	// them as embedded images rather than hyperlinks.
	s = promote_image_links(s)

	return s
}

// promote_image_links rewrites `[name.ext](url)` → `![name.ext](url)` when
// the filename has a recognised image extension and the link is NOT already
// an image embed (i.e. not preceded by `!`).
fn promote_image_links(src string) string {
	image_exts := ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg']
	// Fast path: nothing to do if there are no markdown links at all.
	if !src.contains('](') {
		return src
	}
	mut sb := strings.new_builder(src.len)
	mut i  := 0
	for i < src.len {
		// Look for the pattern [
		if src[i] != `[` {
			sb.write_u8(src[i])
			i++
			continue
		}
		// Check if already an image embed (preceded by !)
		already_image := i > 0 && src[i - 1] == `!`

		// Find the matching ]
		mut j := i + 1
		for j < src.len && src[j] != `]` && src[j] != `\n` {
			j++
		}
		if j >= src.len || src[j] != `]` {
			sb.write_u8(src[i])
			i++
			continue
		}
		// We have [alt_text] at [i..j+1]. Check if followed by (url)
		if j + 1 >= src.len || src[j + 1] != `(` {
			sb.write_u8(src[i])
			i++
			continue
		}
		alt_text := src[i + 1..j]
		// Find matching closing )
		mut k := j + 2
		for k < src.len && src[k] != `)` && src[k] != `\n` {
			k++
		}
		if k >= src.len || src[k] != `)` {
			sb.write_u8(src[i])
			i++
			continue
		}
		url := src[j + 2..k]
		// Decide if the alt_text looks like an image filename
		alt_lower := alt_text.to_lower()
		mut is_image_link := false
		for ext in image_exts {
			if alt_lower.ends_with(ext) {
				is_image_link = true
				break
			}
		}
		// Also treat /user_uploads/ links as images regardless of alt text
		if url.contains('/user_uploads/') {
			is_image_link = true
		}
		if is_image_link && !already_image {
			// Emit as image embed
			sb.write_string('![')
			sb.write_string(alt_text)
			sb.write_string('](')
			sb.write_string(url)
			sb.write_string(')')
		} else {
			// Emit unchanged
			sb.write_string('[')
			sb.write_string(alt_text)
			sb.write_string('](')
			sb.write_string(url)
			sb.write_string(')')
		}
		i = k + 1
	}
	return sb.str()
}

// convert_zulip_quote_blocks rewrites Zulip fenced quote blocks into
// standard `> ` Markdown blockquote lines.  Nested quotes are supported:
// Zulip uses N+1 backticks for the outer fence when the inner uses N, e.g.:
//   ````quote        (4 backticks — outer)
//   ```quote         (3 backticks — inner)
//   …
//   ```              (closes inner)
//   ````             (closes outer)
// Each nesting level prepends one additional `> ` to every body line.
// We process innermost blocks first by repeating until stable.
fn convert_zulip_quote_blocks(src string) string {
	mut s := src
	for {
		next := rewrite_one_quote_pass(s)
		if next == s {
			break
		}
		s = next
	}
	return s
}

// quote_fence_backticks returns the number of leading backticks on `raw`
// (after stripping any `> ` blockquote prefixes) followed by the word
// "quote", indicating a Zulip quote-open fence.  Returns 0 if the line is
// not a quote-open fence.  raw must already have blockquote prefixes stripped.
fn quote_fence_backticks(raw string) int {
	trimmed := raw.trim_space()
	mut n := 0
	for n < trimmed.len && trimmed[n] == 96 { // 96 == backtick
		n++
	}
	if n < 3 {
		return 0
	}
	rest := trimmed[n..].trim_space()
	if rest == 'quote' {
		return n
	}
	return 0
}

// close_fence_backticks returns the number of backticks in a pure closing
// fence line (only backticks after stripping `> ` prefixes), or 0 if it is
// not a pure closing fence.  raw must already have blockquote prefixes stripped.
fn close_fence_backticks(raw string) int {
	trimmed := raw.trim_space()
	if trimmed.len == 0 {
		return 0
	}
	mut n := 0
	for n < trimmed.len && trimmed[n] == 96 {
		n++
	}
	if n == trimmed.len && n >= 3 {
		return n
	}
	return 0
}

// rewrite_one_quote_pass performs one scan, replacing the first (outermost)
// variable-length backtick quote block it finds.  The matching close fence
// must have at least as many backticks as the open fence.  Inner blocks with
// fewer backticks are left in the body to be processed by the next iteration.
//
// Leading `> ` blockquote prefixes are stripped before comparisons so that
// already-converted outer layers do not obscure inner fences.
fn rewrite_one_quote_pass(src string) string {
	lines := src.split('\n')
	mut out      := []string{cap: lines.len + 8}
	mut i        := 0
	mut replaced := false

	for i < lines.len {
		line   := lines[i]
		raw    := strip_blockquote_prefixes(line)
		prefix := line[..line.len - raw.len]

		open_n := quote_fence_backticks(raw)
		if !replaced && open_n >= 3 {
			// Found an opening quote fence with open_n backticks.
			// Collect body lines until a closing fence with >= open_n backticks
			// at the same blockquote prefix depth.
			mut body   := []string{cap: 16}
			i++
			mut closed := false

			for i < lines.len {
				inner      := lines[i]
				inner_raw  := strip_blockquote_prefixes(inner)
				inner_pfx  := inner[..inner.len - inner_raw.len]

				if inner_pfx == prefix {
					close_n := close_fence_backticks(inner_raw)
					if close_n >= open_n {
						closed = true
						i++
						break
					}
				}
				body << inner
				i++
			}

			if !closed {
				// Unclosed block — emit verbatim and move on
				out << line
				for bl in body {
					out << bl
				}
				continue
			}

			// Prefix every body line with one extra `> ` at the open fence's
			// blockquote nesting level.
			for bl in body {
				if bl.starts_with(prefix) {
					out << prefix + '> ' + bl[prefix.len..]
				} else {
					out << prefix + '> ' + bl
				}
			}
			replaced = true
			continue
		}

		out << line
		i++
	}

	return out.join('\n')
}

// strip_blockquote_prefixes removes all leading `> ` / `>` sequences from a
// line, returning the remainder.  Used to look through already-converted outer
// blockquote layers when searching for inner fence markers.
fn strip_blockquote_prefixes(line string) string {
	mut pos := 0
	for pos < line.len {
		if line[pos] == `>` {
			pos++
			if pos < line.len && line[pos] == ` ` {
				pos++
			}
		} else {
			break
		}
	}
	return line[pos..]
}

// strip_html_tags removes HTML tags and decodes common HTML entities.
// This is a simple best-effort pass — not a full HTML parser.
fn strip_html_tags(html string) string {
	mut out := strings.new_builder(html.len)
	mut in_tag := false
	for ch in html.runes() {
		if ch == `<` {
			in_tag = true
			// Replace block-level end tags with newlines for readability
			continue
		}
		if ch == `>` {
			in_tag = false
			continue
		}
		if !in_tag {
			out.write_rune(ch)
		}
	}
	mut result := out.str()
	// Decode common HTML entities
	result = result.replace('&amp;',  '&')
	result = result.replace('&lt;',   '<')
	result = result.replace('&gt;',   '>')
	result = result.replace('&quot;', '"')
	result = result.replace('&#39;',  "'")
	result = result.replace('&nbsp;', ' ')
	return result.trim_space()
}

// ---------------------------------------------------------------------------
// Emoji reactions row
// ---------------------------------------------------------------------------

// ReactionKey groups reactions with the same emoji so we can count them and
// know whether the current user has already reacted.
struct ReactionKey {
	glyph         string // decoded display string (Unicode rune or :name:)
	image_url     string // non-empty for custom/realm emoji: URL to the emoji image
	emoji_name    string
	emoji_code    string
	reaction_type string
}

fn reactions_row(msg ZulipMessage, window &gui.Window) gui.View {
	msg_id := msg.id

	// Aggregate: key = emoji_code, value = count
	mut counts   := map[string]int{}
	mut key_meta := map[string]ReactionKey{}
	mut order    := []string{}

	app      := window.state[App]()
	server   := app.creds.server_url.trim_right('/')

	for r in msg.reactions {
		code := r.emoji_code
		if code !in counts {
			order << code
			key_meta[code] = ReactionKey{
				glyph:         emoji_glyph(r.reaction_type, r.emoji_code, r.emoji_name)
				image_url:     emoji_image_url(server, r.reaction_type, r.emoji_code, r.emoji_name)
				emoji_name:    r.emoji_name
				emoji_code:    r.emoji_code
				reaction_type: r.reaction_type
			}
		}
		counts[code] = (counts[code] or { 0 }) + 1
	}

	mut pills := []gui.View{}
	for code in order {
		count  := counts[code] or { 0 }
		meta   := key_meta[code] or { ReactionKey{} }
		pills << reaction_pill(meta, count, msg_id)
	}

	// "Add reaction" button — always shown so users can react to any message
	pills << add_reaction_button(msg_id, window)

	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(2, 0, 2, 0)
		spacing:     4
		color:       gui.color_transparent
		size_border: 0
		content:     pills
	)
}

// add_reaction_button renders a small "😊+" button that opens the quick
// emoji picker for the given message.  Visibility is tracked in
// App.emoji_picker_open so it survives across frames without animations.
fn add_reaction_button(msg_id int, window &gui.Window) gui.View {
	app     := window.state[App]()
	is_open := app.emoji_picker_open[msg_id] or { false }

	if is_open {
		return emoji_picker_popup(msg_id)
	}

	return gui.button(
		sizing:       gui.fit_fit
		padding:      gui.padding(2, 6, 2, 6)
		color:        gui.color_transparent
		color_hover:  gui.rgba(128, 128, 128, 40)
		color_click:  gui.rgba(128, 128, 128, 60)
		color_border: gui.color_transparent
		size_border:  0
		radius:       10
		tooltip:      &gui.TooltipCfg{ id: 'tt-react-${msg_id}', content: [gui.text(text: 'Add reaction')] }
		content:      [
			gui.text(
				text:       '😊+'
				text_style: gui.TextStyle{
					...gui.theme().n5
					color: gui.theme().color_active
				}
			),
		]
		on_click: fn [msg_id] (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
			mut app := w.state[App]()
			app.emoji_picker_open[msg_id] = true
		}
	)
}

// emoji_picker_popup renders a small inline grid of common emoji that the
// user can click to add as a reaction to the given message.
fn emoji_picker_popup(msg_id int) gui.View {
	// Curated set of common reaction emoji: [name, hex_codepoint]
	common_emoji := [
		['thumbs_up',   '1f44d'],
		['thumbs_down', '1f44e'],
		['heart',       '2764'],
		['laughing',    '1f602'],
		['open_mouth',  '1f62e'],
		['cry',         '1f622'],
		['rage',        '1f621'],
		['tada',        '1f389'],
		['eyes',        '1f440'],
		['fire',        '1f525'],
		['pray',        '1f64f'],
		['clap',        '1f44f'],
		['100',         '1f4af'],
		['check',       '2705'],
		['x',           '274c'],
		['thinking',    '1f914'],
		['wave',        '1f44b'],
		['skull',       '1f480'],
		['heart_eyes',  '1f60d'],
		['sob',         '1f62d'],
	]

	cols_per_row := 5
	mut rows     := []gui.View{}
	mut i        := 0

	for i < common_emoji.len {
		mut row_items := []gui.View{}
		for j := 0; j < cols_per_row && i < common_emoji.len; j++ {
			entry := common_emoji[i]
			ename := entry[0]
			ecode := entry[1]
			glyph := decode_unicode_emoji(ecode)
			row_items << gui.button(
				sizing:       gui.fit_fit
				padding:      gui.padding(4, 6, 4, 6)
				color:        gui.color_transparent
				color_hover:  gui.rgba(128, 128, 128, 50)
				color_click:  gui.rgba(128, 128, 128, 80)
				size_border:  0
				radius:       6
				content:      [
					gui.text(
						text:       glyph
						text_style: gui.theme().b4
					),
				]
				on_click: fn [msg_id, ename, ecode] (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
					action_toggle_reaction(msg_id, ename, ecode, 'unicode_emoji', mut w)
					mut app := w.state[App]()
					app.emoji_picker_open.delete(msg_id)
				}
			)
			i++
		}
		rows << gui.row(
			sizing:      gui.fill_fit
			padding:     gui.padding_none
			spacing:     2
			color:       gui.color_transparent
			size_border: 0
			content:     row_items
		)
	}

	// Close / dismiss row
	rows << gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(2, 0, 0, 0)
		spacing:     0
		color:       gui.color_transparent
		size_border: 0
		content:     [
			gui.button(
				sizing:       gui.fill_fit
				padding:      gui.padding(3, 4, 3, 4)
				color:        gui.color_transparent
				color_hover:  gui.rgba(200, 80, 80, 60)
				size_border:  0
				radius:       4
				content:      [
					gui.text(
						text:       'Close'
						text_style: gui.TextStyle{
							...gui.theme().n5
							color: gui.theme().color_active
						}
					),
				]
				on_click: fn [msg_id] (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
					mut app := w.state[App]()
					app.emoji_picker_open.delete(msg_id)
				}
			),
		]
	)

	return gui.column(
		sizing:       gui.fit_fit
		padding:      gui.padding(6, 6, 6, 6)
		spacing:      2
		color:        gui.theme().color_panel
		color_border: gui.theme().color_border
		size_border:  1
		radius:       gui.theme().radius_medium
		content:      rows
	)
}

fn reaction_pill(meta ReactionKey, count int, msg_id int) gui.View {
	glyph      := meta.glyph
	image_url  := meta.image_url
	emoji_name := meta.emoji_name
	emoji_code := meta.emoji_code
	rtype      := meta.reaction_type

	// Emoji display: image for custom emoji, text glyph for unicode emoji
	emoji_view := if image_url.len > 0 {
		gui.View(gui.image(
			src:    image_url
			width:  18
			height: 18
			sizing: gui.fixed_fixed
		))
	} else {
		gui.View(gui.text(
			text:       glyph
			text_style: gui.TextStyle{
				...gui.theme().b4
			}
		))
	}

	return gui.button(
		sizing:       gui.fit_fit
		padding:      gui.padding(3, 7, 3, 7)
		color:        gui.rgba(128, 128, 128, 25)
		color_hover:  gui.rgba(128, 128, 128, 50)
		color_click:  gui.rgba(128, 128, 128, 70)
		color_border: gui.rgba(128, 128, 128, 55)
		size_border:  1
		radius:       10
		content:      [
			gui.row(
				spacing:     4
				padding:     gui.padding_none
				color:       gui.color_transparent
				size_border: 0
				v_align:     .middle
				content:     [
					emoji_view,
					gui.text(
						text:       '${count}'
						text_style: gui.TextStyle{
							...gui.theme().n5
							color: gui.theme().color_active
						}
					),
				]
			),
		]
		on_click: fn [msg_id, emoji_name, emoji_code, rtype] (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
			action_toggle_reaction(msg_id, emoji_name, emoji_code, rtype, mut w)
		}
	)
}

// emoji_glyph decodes a Zulip emoji into a displayable string.
// For unicode_emoji, converts the dash-separated hex codepoints to UTF-8.
// For others (realm_emoji, zulip_extra_emoji) returns :name: as a fallback —
// callers should prefer emoji_image_url() which returns a proper image URL.
fn emoji_glyph(reaction_type string, emoji_code string, emoji_name string) string {
	if reaction_type == 'unicode_emoji' {
		return decode_unicode_emoji(emoji_code)
	}
	return ':${emoji_name}:'
}

// emoji_image_url returns a URL for rendering a non-unicode Zulip emoji as an
// image.  Returns an empty string for unicode_emoji (use emoji_glyph instead).
//
// Zulip emoji URL patterns:
//   realm_emoji      → {server}/user_uploads/realm_emoji/{realm_id}/{code}.png
//                      but code here is a numeric ID; we use the emoji name
//                      path that Zulip also exposes:
//                      {server}/static/generated/emoji/images-google-64/{name}.png
//                      Actually for realm emoji the reliable path is:
//                      {server}/user_uploads/realm_emoji/{code} (code is numeric ID)
//   zulip_extra_emoji → {server}/static/generated/emoji/images-google-64/{code}.png
//
// In practice the most reliable approach for realm_emoji is using the
// /api/v1/realm/emoji endpoint, but since we don't cache that, we use
// the static path which works for built-in zulip_extra_emoji and falls
// back to :name: text for realm_emoji we can't resolve.
fn emoji_image_url(server string, reaction_type string, emoji_code string, emoji_name string) string {
	match reaction_type {
		'zulip_extra_emoji' {
			// Zulip ships extra emoji as PNG files named by their code
			return '${server}/static/generated/emoji/images-google-64/${emoji_code}.png'
		}
		'realm_emoji' {
			// Realm (server-custom) emoji: code is numeric ID, image served at:
			// /user_uploads/realm_emoji/{id}/emoji_name.png  — but the exact
			// path depends on the server version.  Use the name-based API path
			// which most Zulip servers expose for custom emoji.
			return '${server}/user_uploads/realm_emoji/${emoji_code}/${emoji_name}.png'
		}
		else {
			return ''
		}
	}
}

// decode_unicode_emoji converts a Zulip emoji_code like "1f44d" or "1f1fa-1f1f8"
// (dash-separated hex codepoints) into a UTF-8 string.
fn decode_unicode_emoji(code string) string {
	parts := code.split('-')
	mut runes := []rune{}
	for part in parts {
		cp := u32(part.parse_uint(16, 32) or { continue })
		runes << rune(cp)
	}
	if runes.len == 0 {
		return ':?:'
	}
	return runes.string()
}

// ---------------------------------------------------------------------------
// Compose area
// ---------------------------------------------------------------------------

const id_focus_compose   = u32(30)
const id_focus_messages  = u32(21)

fn compose_area(window &gui.Window) gui.View {
	app := window.state[App]()
	conv := app.active_conv or {
		// No conversation — hide compose
		return gui.rectangle(
			sizing:      gui.fill_fixed
			height:      0
			color:       gui.color_transparent
			size_border: 0
		)
	}

	placeholder := match conv.kind {
		.stream  { 'Message #${conv.stream_name} > ${conv.topic}' }
		.direct  { 'Message ${conv.dm_name}' }
	}

	compose_text := app.compose_text
	is_loading   := app.compose_loading

	return gui.column(
		sizing:       gui.fill_fit
		padding:      gui.padding(0, 0, 0, 0)
		spacing:      0
		color:        gui.theme().color_background
		content:      [
			gui.rectangle(
				sizing:      gui.fill_fixed
				height:      1
				color:       gui.theme().color_border
				size_border: 0
			),
			gui.row(
				sizing:      gui.fill_fit
				padding:     gui.padding(10, 12, 10, 12)
				spacing:     8
				color:       gui.color_transparent
				size_border: 0
				v_align:     .bottom
				content:     [
					gui.input(
						id_focus:        id_focus_compose
						sizing:          gui.fill_fit
						mode:            .multiline
						text:            compose_text
						placeholder:     placeholder
						min_height:      38
						max_height:      160
						size_border:     1
						radius:          gui.theme().radius_medium
						on_text_changed: fn (_ &gui.Layout, s string, mut w gui.Window) {
							w.state[App]().compose_text = s
						}
						on_text_commit:  fn (_ &gui.Layout, s string, _ gui.InputCommitReason, mut w gui.Window) {
							action_send_message(mut w)
						}
					),
					gui.button(
							padding:     gui.padding(8, 10, 8, 10)
							disabled:    is_loading
							tooltip:     &gui.TooltipCfg{ id: 'tt-attach', content: [gui.text(text: 'Attach file')] }
							color:       gui.color_transparent
							color_hover: gui.rgba(128, 128, 128, 40)
							size_border: 0
							content:     [
								gui.text(
									text:       gui.icon_upload
									text_style: gui.theme().icon4
								),
							]
							on_click: fn (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
								action_pick_and_upload_file(mut w)
							}
						),
						gui.button(
							id_focus:    31
							padding:     gui.padding(8, 12, 8, 12)
							disabled:    is_loading || compose_text.trim_space().len == 0
							tooltip:     &gui.TooltipCfg{ id: 'tt-send', content: [gui.text(text: 'Send (Enter)')] }
							content:     [
								gui.text(
									text:       if is_loading { gui.icon_sync } else { gui.icon_paper_plane }
									text_style: gui.theme().icon4
								),
							]
							on_click: fn (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
								action_send_message(mut w)
							}
						),
				]
			),
		]
	)
}

// ---------------------------------------------------------------------------
// Internal narrow-link navigation
// ---------------------------------------------------------------------------

// make_link_handler returns a closure that intercepts Zulip internal narrow
// links and navigates within the app; external links open in the browser.
fn make_link_handler(server_url string) fn (string, mut gui.Event, mut gui.Window) {
	return fn [server_url] (url string, mut e gui.Event, mut w gui.Window) {
		// Try to parse as a Zulip narrow link for the current server
		if nav := parse_narrow_link(url, server_url) {
			e.is_handled = true
			action_open_topic(nav.stream_id, nav.stream_name, nav.topic, mut w)
			return
		}
		// Fall through: let the default handler open it in the browser
	}
}

struct NarrowNav {
	stream_id   int
	stream_name string
	topic       string
}

// parse_narrow_link attempts to decode a Zulip narrow URL into a NarrowNav.
// Supports both fragment-based and path-based formats:
//   https://realm/#narrow/stream/42-name/topic/My+Topic/near/1234
//   https://realm/#narrow/channel/42-name/topic/My+Topic
fn parse_narrow_link(url string, server_url string) ?NarrowNav {
	// Must start with the current server URL (or be a fragment-only link)
	trimmed_server := server_url.trim_right('/')
	mut fragment := ''
	if url.starts_with(trimmed_server) {
		rest := url[trimmed_server.len..]
		hash_idx := rest.index('#') or { return none }
		fragment = rest[hash_idx + 1..]
	} else if url.starts_with('#') {
		fragment = url[1..]
	} else {
		return none
	}

	// fragment looks like: narrow/stream/42-mystream/topic/My+Topic/near/99
	if !fragment.starts_with('narrow/') {
		return none
	}
	parts := fragment.split('/')
	// parts[0]='narrow', parts[1]='stream'|'channel', parts[2]='42-name', parts[3]='topic', parts[4]=topicname
	if parts.len < 5 {
		return none
	}
	if parts[1] != 'stream' && parts[1] != 'channel' {
		return none
	}
	if parts[3] != 'topic' {
		return none
	}

	// Parse stream_id from "42-mystream"
	stream_slug := parts[2]
	dash_idx := stream_slug.index('-') or { return none }
	stream_id := stream_slug[..dash_idx].int()
	stream_name_encoded := stream_slug[dash_idx + 1..]
	// Decode percent-encoding and replace dots used for spaces in Zulip URLs
	stream_name := urllib.query_unescape(stream_name_encoded.replace('.', ' ')) or {
		stream_name_encoded
	}

	// Topic may be URL-encoded; Zulip also uses dots for spaces in topics
	topic_encoded := parts[4]
	topic := urllib.query_unescape(topic_encoded.replace('.', ' ')) or { topic_encoded }

	return NarrowNav{
		stream_id:   stream_id
		stream_name: stream_name
		topic:       topic
	}
}

// ---------------------------------------------------------------------------
// Shared spacers
// ---------------------------------------------------------------------------

fn empty_spacer() gui.View {
	return gui.rectangle(
		width:       0
		height:      0
		sizing:      gui.fixed_fixed
		color:       gui.color_transparent
		size_border: 0
	)
}

// ---------------------------------------------------------------------------
// Timestamp helpers
// ---------------------------------------------------------------------------

fn format_time(unix_ts i64) string {
	t := time.unix(unix_ts)
	h  := t.hour
	m  := t.minute
	am := if h < 12 { 'AM' } else { 'PM' }
	h12 := if h % 12 == 0 { 12 } else { h % 12 }
	return '${h12}:${m:02d} ${am}'
}

fn format_date(unix_ts i64) string {
	now := time.now()
	t   := time.unix(unix_ts)
	if t.year == now.year && t.month == now.month && t.day == now.day {
		return 'Today'
	}
	yesterday := now.add(-24 * time.hour)
	if t.year == yesterday.year && t.month == yesterday.month && t.day == yesterday.day {
		return 'Yesterday'
	}
	months := ['January', 'February', 'March', 'April', 'May', 'June',
	           'July', 'August', 'September', 'October', 'November', 'December']
	month_name := if int(t.month) >= 1 && int(t.month) <= 12 {
		months[int(t.month) - 1]
	} else {
		'Unknown'
	}
	return '${month_name} ${t.day}, ${t.year}'
}
