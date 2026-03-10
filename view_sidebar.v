module main

import gui

// ---------------------------------------------------------------------------
// Sidebar scroll id
// ---------------------------------------------------------------------------

const id_scroll_sidebar = u32(10)

// ---------------------------------------------------------------------------
// Top-level sidebar view
// ---------------------------------------------------------------------------

fn view_sidebar(window &gui.Window) gui.View {
	app := window.state[App]()

	return gui.column(
		sizing:    gui.fill_fill
		spacing:   0
		padding:   gui.padding_none
		color:     sidebar_bg()
		id_scroll: id_scroll_sidebar
		scrollbar_cfg_y: &gui.ScrollbarCfg{
			overflow: .auto
		}
		content: [
			sidebar_header(app),
			sidebar_divider(),
			sidebar_streams_section(app),
		]
	)
}

// ---------------------------------------------------------------------------
// Header: current user info + logout button
// ---------------------------------------------------------------------------

fn sidebar_header(app &App) gui.View {
	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(12, 14, 12, 14)
		spacing:     10
		color:       gui.color_transparent
		size_border: 0
		v_align:     .middle
		content:     [
			// Avatar circle
			gui.column(
				clip:        true
				width:       36
				height:      36
				sizing:      gui.fixed_fixed
				color:       accent_color()
				radius:      18
				h_align:     .center
				v_align:     .middle
				size_border: 0
				padding:     gui.padding_none
				content:     [
					if app.me.avatar_url.len > 0 {
						gui.image(
							src:    app.me.avatar_url
							width:  36
							height: 36
							sizing: gui.fill_fill
						)
					} else {
						gui.text(
							text:       initials(app.me.full_name)
							text_style: gui.TextStyle{
								...gui.theme().b4
								color: gui.white
							}
						)
					},
				]
			),
			// Name + server
			gui.column(
				sizing:  gui.fill_fit
				spacing: 2
				padding: gui.padding_none
				content: [
					gui.text(
						text:       if app.me.full_name.len > 0 { app.me.full_name } else { 'Loading...' }
						text_style: gui.TextStyle{
							...gui.theme().b4
							color: sidebar_fg()
						}
					),
					gui.text(
						text:       short_server(app.creds.server_url)
						text_style: gui.TextStyle{
							...gui.theme().n5
							color: sidebar_fg_dim()
						}
					),
				]
			),
			// Logout button
			gui.button(
				padding:     gui.padding(4, 6, 4, 6)
				size_border: 0
				radius:      gui.theme().radius_small
				color:       gui.color_transparent
				color_hover: gui.rgba(255, 255, 255, 25)
				color_click: gui.rgba(255, 255, 255, 40)
				tooltip:     &gui.TooltipCfg{ id: 'tt-logout', content: [gui.text(text: 'Sign out')] }
				content:     [
					gui.text(
						text:       gui.icon_logout
						text_style: gui.TextStyle{
							...gui.theme().icon4
							color: sidebar_fg_dim()
						}
					),
				]
				on_click: fn (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
					action_logout(mut w)
				}
			),
		]
	)
}

// ---------------------------------------------------------------------------
// Streams section header
// ---------------------------------------------------------------------------

fn sidebar_streams_section(app &App) gui.View {
	return gui.column(
		sizing:  gui.fill_fit
		spacing: 0
		padding: gui.padding_none
		content: [
			sidebar_section_label('CHANNELS'),
			streams_list(app),
		]
	)
}

fn sidebar_section_label(label string) gui.View {
	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(10, 14, 4, 14)
		spacing:     6
		color:       gui.color_transparent
		size_border: 0
		v_align:     .middle
		content:     [
			gui.text(
				text:       label
				text_style: gui.TextStyle{
					...gui.theme().n5
					color: sidebar_fg_dim()
				}
			),
		]
	)
}

// ---------------------------------------------------------------------------
// Stream list
// ---------------------------------------------------------------------------

fn streams_list(app &App) gui.View {
	if app.streams_loading {
		return gui.column(
			sizing:  gui.fill_fit
			padding: gui.padding(16, 14, 16, 14)
			content: [
				gui.row(
					spacing: 8
					padding: gui.padding_none
					color:   gui.color_transparent
					size_border: 0
					v_align: .middle
					content: [
						gui.text(
							text:       gui.icon_sync
							text_style: gui.TextStyle{
								...gui.theme().icon4
								color: sidebar_fg_dim()
							}
						),
						gui.text(
							text:       'Loading channels…'
							text_style: gui.TextStyle{
								...gui.theme().n4
								color: sidebar_fg_dim()
							}
						),
					]
				),
			]
		)
	}

	if app.streams_error.len > 0 {
		return gui.column(
			sizing:  gui.fill_fit
			padding: gui.padding(12, 14, 12, 14)
			content: [
				gui.text(
					text:       app.streams_error
					mode:       .wrap
					text_style: gui.TextStyle{
						...gui.theme().n4
						color: gui.rgb(220, 80, 80)
					}
				),
			]
		)
	}

	mut items := []gui.View{}
	for stream in app.streams {
		items << stream_row(stream, app)
		if app.is_expanded(stream.stream_id) {
			if app.topics_loading[stream.stream_id] or { false } {
				items << topics_loading_row()
			} else {
				topics := app.topics_for(stream.stream_id)
				if topics.len == 0 {
					items << topics_empty_row()
				} else {
					for topic in topics {
						items << topic_row(stream, topic, app)
					}
				}
			}
		}
	}

	if items.len == 0 {
		return gui.column(
			sizing:  gui.fill_fit
			padding: gui.padding(12, 14, 12, 14)
			content: [
				gui.text(
					text:       'No channels found.'
					text_style: gui.TextStyle{
						...gui.theme().n4
						color: sidebar_fg_dim()
					}
				),
			]
		)
	}

	return gui.column(
		sizing:  gui.fill_fit
		spacing: 0
		padding: gui.padding_none
		content: items
	)
}

// ---------------------------------------------------------------------------
// Stream row
// ---------------------------------------------------------------------------

fn stream_row(stream ZulipStream, app &App) gui.View {
	is_expanded := app.is_expanded(stream.stream_id)
	stream_id := stream.stream_id
	stream_name := stream.name

	// Determine if any topic in this stream is the active conversation
	is_active_stream := if conv := app.active_conv {
		conv.kind == .stream && conv.stream_id == stream.stream_id
	} else {
		false
	}

	row_color := if is_active_stream {
		gui.rgba(255, 255, 255, 18)
	} else {
		gui.color_transparent
	}

	chevron := if is_expanded { gui.icon_drop_down } else { gui.icon_drop_right }
	lock_icon := if stream.invite_only { gui.icon_lock } else { gui.icon_hash }

	return gui.button(
		sizing:      gui.fill_fit
		h_align:     .start
		padding:     gui.padding_none
		radius:      0
		size_border: 0
		color:       row_color
		color_hover: gui.rgba(255, 255, 255, 12)
		color_click: gui.rgba(255, 255, 255, 22)
		content:     [
			gui.row(
				sizing:      gui.fill_fit
				padding:     gui.padding(6, 10, 6, 10)
				spacing:     6
				color:       gui.color_transparent
				size_border: 0
				v_align:     .middle
				content:     [
					// Chevron
					gui.text(
						text:       chevron
						text_style: gui.TextStyle{
							...gui.theme().icon5
							color: sidebar_fg_dim()
						}
					),
					// Hash / lock icon with stream color dot
					stream_color_dot(stream.color),
					gui.text(
						text:       lock_icon
						text_style: gui.TextStyle{
							...gui.theme().icon5
							color: sidebar_fg_dim()
						}
					),
					gui.text(
						text:       stream_name
						text_style: gui.TextStyle{
							...gui.theme().n4
							color: sidebar_fg()
						}
					),
				]
			),
		]
		on_click: fn [stream_id] (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
			action_toggle_stream(stream_id, mut w)
		}
	)
}

// ---------------------------------------------------------------------------
// Topics loading / empty rows
// ---------------------------------------------------------------------------

fn topics_loading_row() gui.View {
	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(5, 10, 5, 34)
		spacing:     6
		color:       gui.color_transparent
		size_border: 0
		v_align:     .middle
		content:     [
			gui.text(
				text:       gui.icon_sync
				text_style: gui.TextStyle{
					...gui.theme().icon5
					color: sidebar_fg_dim()
				}
			),
			gui.text(
				text:       'Loading…'
				text_style: gui.TextStyle{
					...gui.theme().n5
					color: sidebar_fg_dim()
				}
			),
		]
	)
}

fn topics_empty_row() gui.View {
	return gui.row(
		sizing:      gui.fill_fit
		padding:     gui.padding(5, 10, 5, 34)
		spacing:     6
		color:       gui.color_transparent
		size_border: 0
		v_align:     .middle
		content:     [
			gui.text(
				text:       'No topics yet'
				text_style: gui.TextStyle{
					...gui.theme().n5
					color: sidebar_fg_dim()
				}
			),
		]
	)
}

// ---------------------------------------------------------------------------
// Topic row
// ---------------------------------------------------------------------------

fn topic_row(stream ZulipStream, topic ZulipTopic, app &App) gui.View {
	stream_id   := stream.stream_id
	stream_name := stream.name
	topic_name  := topic.name

	is_active := if conv := app.active_conv {
		conv.kind == .stream && conv.stream_id == stream_id && conv.topic == topic_name
	} else {
		false
	}

	row_color := if is_active {
		gui.rgba(255, 255, 255, 28)
	} else {
		gui.color_transparent
	}

	label_style := if is_active {
		gui.TextStyle{
			...gui.theme().b4
			color: gui.white
		}
	} else {
		gui.TextStyle{
			...gui.theme().n4
			color: sidebar_fg_muted()
		}
	}

	return gui.button(
		sizing:      gui.fill_fit
		h_align:     .start
		padding:     gui.padding_none
		radius:      0
		size_border: 0
		color:       row_color
		color_hover: gui.rgba(255, 255, 255, 12)
		color_click: gui.rgba(255, 255, 255, 22)
		content:     [
			gui.row(
				sizing:      gui.fill_fit
				padding:     gui.padding(5, 10, 5, 34)
				spacing:     6
				color:       gui.color_transparent
				size_border: 0
				v_align:     .middle
				content:     [
					gui.text(
						text:       gui.icon_comment
						text_style: gui.TextStyle{
							...gui.theme().icon5
							color: sidebar_fg_dim()
						}
					),
					gui.text(
						text:       topic_name
						text_style: label_style
					),
				]
			),
		]
		on_click: fn [stream_id, stream_name, topic_name] (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
			action_open_topic(stream_id, stream_name, topic_name, mut w)
		}
	)
}

// ---------------------------------------------------------------------------
// Stream color dot widget
// ---------------------------------------------------------------------------

fn stream_color_dot(hex_color string) gui.View {
	c := parse_hex_color(hex_color)
	return gui.rectangle(
		width:       8
		height:      8
		sizing:      gui.fixed_fixed
		radius:      4
		color:       c
		size_border: 0
	)
}

// ---------------------------------------------------------------------------
// Sidebar divider
// ---------------------------------------------------------------------------

fn sidebar_divider() gui.View {
	return gui.rectangle(
		sizing:       gui.fill_fixed
		height:       1
		color:        gui.rgba(255, 255, 255, 20)
		size_border:  0
	)
}

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

fn sidebar_bg() gui.Color {
	return gui.Color{ r: 30, g: 33, b: 40, a: 255 }
}

fn sidebar_fg() gui.Color {
	return gui.Color{ r: 220, g: 222, b: 228, a: 255 }
}

fn sidebar_fg_muted() gui.Color {
	return gui.Color{ r: 180, g: 183, b: 192, a: 255 }
}

fn sidebar_fg_dim() gui.Color {
	return gui.Color{ r: 120, g: 124, b: 138, a: 255 }
}

fn accent_color() gui.Color {
	return gui.Color{ r: 100, g: 110, b: 230, a: 255 }
}

// parse_hex_color converts a "#RRGGBB" string to a gui.Color.
// Falls back to a neutral gray on parse failure.
fn parse_hex_color(hex string) gui.Color {
	s := hex.trim_left('#')
	if s.len != 6 {
		return gui.Color{ r: 120, g: 124, b: 138, a: 255 }
	}
	r := s[0..2].parse_uint(16, 8) or { 128 }
	g := s[2..4].parse_uint(16, 8) or { 128 }
	b := s[4..6].parse_uint(16, 8) or { 128 }
	return gui.Color{ r: u8(r), g: u8(g), b: u8(b), a: 255 }
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

// initials returns up to 2 capital letters from a full name.
fn initials(name string) string {
	parts := name.split(' ')
	if parts.len == 0 || (parts.len == 1 && parts[0].len == 0) {
		return '?'
	}
	if parts.len == 1 {
		return parts[0][..1].to_upper()
	}
	a := parts[0][..1].to_upper()
	b := parts[parts.len - 1][..1].to_upper()
	return '${a}${b}'
}

// short_server trims the protocol and trailing slash from a URL for display.
fn short_server(url string) string {
	s := url.trim_right('/')
	if s.starts_with('https://') {
		return s[8..]
	}
	if s.starts_with('http://') {
		return s[7..]
	}
	return s
}
