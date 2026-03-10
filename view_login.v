module main

import gui

// ---------------------------------------------------------------------------
// Login screen
// ---------------------------------------------------------------------------

const id_focus_server  = u32(1)
const id_focus_email   = u32(2)
const id_focus_api_key = u32(3)
const id_focus_submit  = u32(4)

fn view_login(window &gui.Window) gui.View {
	w, h := window.window_size()
	app := window.state[App]()

	card_width := 420

	return gui.column(
		width:   w
		height:  h
		sizing:  gui.fixed_fixed
		h_align: .center
		v_align: .middle
		color:   gui.theme().color_background
		content: [
			// ---- Card ----
			gui.column(
				width:        card_width
				sizing:       gui.fixed_fit
				padding:      gui.padding(32, 32, 32, 32)
				spacing:      16
				color:        gui.theme().color_panel
				color_border: gui.theme().color_border
				size_border:  1
				radius:       gui.theme().radius_medium
				content:      [
					// Title
					gui.column(
						sizing:  gui.fill_fit
						spacing: 4
						padding: gui.padding_none
						content: [
							gui.text(
								text:       'Visp'
								text_style: gui.TextStyle{
									...gui.theme().b1
									size: 28
								}
							),
							gui.text(
								text:       'Sign in to your Zulip server'
								text_style: gui.theme().n4
							),
						]
					),
					// Divider
					gui.rectangle(
						sizing:      gui.fill_fixed
						height:      1
						color:       gui.theme().color_border
						size_border: 0
					),
					// Server URL field
					login_field(LoginFieldCfg{
						label:       'Server URL'
						placeholder: 'https://your-org.zulipchat.com'
						text:        app.login_server
						id_focus:    id_focus_server
						on_change:   fn (_ &gui.Layout, s string, mut w gui.Window) {
							w.state[App]().login_server = s
						}
					}),
					// Email field
					login_field(LoginFieldCfg{
						label:       'Email / Bot email'
						placeholder: 'you@example.com'
						text:        app.login_email
						id_focus:    id_focus_email
						on_change:   fn (_ &gui.Layout, s string, mut w gui.Window) {
							w.state[App]().login_email = s
						}
					}),
					// API key field
					login_field(LoginFieldCfg{
						label:       'API key'
						placeholder: 'Your Zulip API key'
						text:        app.login_api_key
						id_focus:    id_focus_api_key
						is_password: true
						on_change:   fn (_ &gui.Layout, s string, mut w gui.Window) {
							w.state[App]().login_api_key = s
						}
					}),
					// Error message (always present, transparent when empty)
					login_error_text(app.login_error),
					// Sign in button
					gui.button(
						id_focus: id_focus_submit
						sizing:   gui.fill_fit
						disabled: app.login_loading
						content:  [
							gui.text(
								text: if app.login_loading {
									'Signing in...'
								} else {
									'Sign in'
								}
							),
						]
						on_click: fn (_ &gui.Layout, mut _ gui.Event, mut w gui.Window) {
							action_login(mut w)
						}
					),
					// Help text
					gui.text(
						text:       'Find your API key at Settings → Account & privacy → API key'
						mode:       .wrap
						text_style: gui.TextStyle{
							...gui.theme().n5
							color: gui.theme().color_active
						}
					),
				]
			),
		]
	)
}

// login_error_text returns a text widget showing the error, or a zero-height
// spacer when there is no error, so the card layout stays stable.
fn login_error_text(msg string) gui.View {
	if msg.len == 0 {
		return gui.rectangle(
			sizing:      gui.fill_fixed
			height:      0
			color:       gui.color_transparent
			size_border: 0
		)
	}
	return gui.text(
		text:       msg
		mode:       .wrap
		text_style: gui.TextStyle{
			...gui.theme().n4
			color: gui.rgb(220, 80, 80)
		}
	)
}

// ---------------------------------------------------------------------------
// Helper: labelled input field
// ---------------------------------------------------------------------------

struct LoginFieldCfg {
	label       string
	placeholder string
	text        string
	id_focus    u32
	is_password bool
	on_change   fn (&gui.Layout, string, mut gui.Window) = unsafe { nil }
}

fn login_field(cfg LoginFieldCfg) gui.View {
	return gui.column(
		sizing:  gui.fill_fit
		spacing: 6
		padding: gui.padding_none
		content: [
			gui.text(
				text:       cfg.label
				text_style: gui.theme().b4
			),
			gui.input(
				id_focus:        cfg.id_focus
				sizing:          gui.fill_fit
				text:            cfg.text
				placeholder:     cfg.placeholder
				is_password:     cfg.is_password
				size_border:     1
				on_text_changed: cfg.on_change
			),
		]
	)
}
