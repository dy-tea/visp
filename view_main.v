module main

import gui

// ---------------------------------------------------------------------------
// Main application view — composes sidebar + messages panel
// ---------------------------------------------------------------------------

fn view_main(window &gui.Window) gui.View {
	w, h := window.window_size()

	sidebar_width := 260

	return gui.row(
		width:   w
		height:  h
		sizing:  gui.fixed_fixed
		spacing: 0
		padding: gui.padding_none
		color:   gui.theme().color_background
		content: [
			// ---- Sidebar ----
			gui.column(
				width:       sidebar_width
				sizing:      gui.fixed_fill
				spacing:     0
				padding:     gui.padding_none
				color:       sidebar_bg()
				size_border: 0
				content:     [
					view_sidebar(window),
				]
			),
			// ---- Vertical divider ----
			gui.rectangle(
				width:       1
				sizing:      gui.fixed_fill
				color:       gui.rgba(255, 255, 255, 15)
				size_border: 0
			),
			// ---- Messages panel ----
			gui.column(
				sizing:  gui.fill_fill
				spacing: 0
				padding: gui.padding_none
				content: [
					view_messages_panel(window),
				]
			),
		]
	)
}
