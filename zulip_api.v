module main

import net.http
import json
import os
import strings
import net.urllib
import encoding.base64


// ---------------------------------------------------------------------------
// Credential storage
// ---------------------------------------------------------------------------

pub struct ZulipCredentials {
pub mut:
	server_url string
	email      string
	api_key    string
}

fn (c &ZulipCredentials) is_valid() bool {
	return c.server_url.len > 0 && c.email.len > 0 && c.api_key.len > 0
}

fn credentials_path() string {
	return os.join_path(os.home_dir(), '.config', 'visp', 'credentials.json')
}

fn save_credentials(creds ZulipCredentials) ! {
	dir := os.dir(credentials_path())
	if !os.exists(dir) {
		os.mkdir_all(dir)!
	}
	os.write_file(credentials_path(), json.encode(creds))!
}

fn load_credentials() ?ZulipCredentials {
	data := os.read_file(credentials_path()) or { return none }
	creds := json.decode(ZulipCredentials, data) or { return none }
	if !creds.is_valid() {
		return none
	}
	return creds
}

// ---------------------------------------------------------------------------
// Zulip REST API types
// ---------------------------------------------------------------------------

pub struct ZulipUser {
pub mut:
	user_id     int    @[json: 'user_id']
	full_name   string @[json: 'full_name']
	email       string @[json: 'email']
	avatar_url  string @[json: 'avatar_url']
	is_bot      bool   @[json: 'is_bot']
	is_active   bool   @[json: 'is_active']
}

pub struct ZulipStream {
pub mut:
	stream_id   int    @[json: 'stream_id']
	name        string @[json: 'name']
	description string @[json: 'description']
	color       string @[json: 'color']
	invite_only bool   @[json: 'invite_only']
}

pub struct ZulipMessage {
pub mut:
	id              int    @[json: 'id']
	sender_id       int    @[json: 'sender_id']
	sender_full_name string @[json: 'sender_full_name']
	sender_email    string @[json: 'sender_email']
	avatar_url      string @[json: 'avatar_url']
	content         string @[json: 'content']
	content_type    string @[json: 'content_type']
	timestamp       i64    @[json: 'timestamp']
	stream_id       int    @[json: 'stream_id']
	subject         string @[json: 'subject']
	msg_type        string @[json: 'type']
	display_recipient string @[json: 'display_recipient']
	reactions       []ZulipReaction @[json: 'reactions']
}

pub struct ZulipReaction {
pub mut:
	emoji_name    string @[json: 'emoji_name']
	emoji_code    string @[json: 'emoji_code']
	reaction_type string @[json: 'reaction_type']
	user_id       int    @[json: 'user_id']
}

pub struct ZulipTopic {
pub mut:
	name       string @[json: 'name']
	max_id     int    @[json: 'max_id']
}

// ---------------------------------------------------------------------------
// API response wrappers
// ---------------------------------------------------------------------------

struct StreamsResponse {
	result  string        @[json: 'result']
	streams []ZulipStream @[json: 'streams']
}

struct ZulipSubscription {
pub mut:
	stream_id   int    @[json: 'stream_id']
	name        string @[json: 'name']
	description string @[json: 'description']
	color       string @[json: 'color']
	invite_only bool   @[json: 'invite_only']
}

struct SubscriptionsResponse {
	result        string              @[json: 'result']
	subscriptions []ZulipSubscription @[json: 'subscriptions']
}

struct MessagesResponse {
	result   string         @[json: 'result']
	messages []ZulipMessage @[json: 'messages']
}

struct SendMessageResponse {
	result string @[json: 'result']
	id     int    @[json: 'id']
	msg    string @[json: 'msg']
}

struct TopicsResponse {
	result string       @[json: 'result']
	topics []ZulipTopic @[json: 'topics']
}

struct ProfileResponse {
	result      string    @[json: 'result']
	user_id     int       @[json: 'user_id']
	full_name   string    @[json: 'full_name']
	email       string    @[json: 'email']
	avatar_url  string    @[json: 'avatar_url']
}

// ---------------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------------

pub struct ZulipClient {
pub mut:
	creds ZulipCredentials
}

fn (c &ZulipClient) base_url() string {
	url := c.creds.server_url.trim_right('/')
	return '${url}/api/v1'
}

fn (c &ZulipClient) auth_header() string {
	encoded := base64.encode_str('${c.creds.email}:${c.creds.api_key}')
	return 'Basic ${encoded}'
}

fn (c &ZulipClient) get(path string) !string {
	url := '${c.base_url()}${path}'
	mut req := http.Request{
		method: .get
		url:    url
	}
	req.add_header(.authorization, c.auth_header())
	resp := req.do()!
	if resp.status_code != 200 {
		return error('HTTP ${resp.status_code}: ${resp.body}')
	}
	return resp.body
}

fn (c &ZulipClient) post(path string, data string) !string {
	url := '${c.base_url()}${path}'
	mut req := http.Request{
		method:      .post
		url:         url
		data:        data
		header:      http.new_header_from_map({
			http.CommonHeader.content_type: 'application/x-www-form-urlencoded'
		})
	}
	req.add_header(.authorization, c.auth_header())
	resp := req.do()!
	if resp.status_code != 200 {
		return error('HTTP ${resp.status_code}: ${resp.body}')
	}
	return resp.body
}

// ---------------------------------------------------------------------------
// Public API methods
// ---------------------------------------------------------------------------

pub fn (c &ZulipClient) fetch_profile() !ZulipUser {
	body := c.get('/users/me')!
	resp := json.decode(ProfileResponse, body)!
	server := c.creds.server_url.trim_right('/')
	return ZulipUser{
		user_id:    resp.user_id
		full_name:  resp.full_name
		email:      resp.email
		avatar_url: resolve_url(server, resp.avatar_url)
		is_active:  true
	}
}

pub fn (c &ZulipClient) fetch_subscribed_streams() ![]ZulipStream {
	body := c.get('/users/me/subscriptions')!
	resp := json.decode(SubscriptionsResponse, body)!
	if resp.result != 'success' {
		return error('fetch_subscribed_streams: ${resp.result}')
	}
	mut streams := []ZulipStream{}
	for sub in resp.subscriptions {
		streams << ZulipStream{
			stream_id:   sub.stream_id
			name:        sub.name
			description: sub.description
			color:       sub.color
			invite_only: sub.invite_only
		}
	}
	streams.sort(a.name < b.name)
	return streams
}

pub fn (c &ZulipClient) fetch_topics(stream_id int) ![]ZulipTopic {
	body := c.get('/users/me/${stream_id}/topics')!
	resp := json.decode(TopicsResponse, body)!
	if resp.result != 'success' {
		return error('fetch_topics: ${resp.result}')
	}
	mut topics := resp.topics.clone()
	topics.sort(a.max_id > b.max_id)
	return topics
}

pub fn (c &ZulipClient) fetch_messages(narrow string, num_before int, num_after int, anchor string) ![]ZulipMessage {
	encoded_narrow := urllib.path_escape(narrow)
	// client_gravatar=false: always return full absolute avatar URLs (no null for gravatar users)
	path := '/messages?narrow=${encoded_narrow}&num_before=${num_before}&num_after=${num_after}&anchor=${anchor}&apply_markdown=false&client_gravatar=false'
	body := c.get(path)!
	resp := json.decode(MessagesResponse, body)!
	if resp.result != 'success' {
		return error('fetch_messages: ${resp.result}')
	}
	// Resolve relative URLs on every returned message
	server := c.creds.server_url.trim_right('/')
	mut msgs := resp.messages.clone()
	for i in 0 .. msgs.len {
		msgs[i].avatar_url = resolve_url(server, msgs[i].avatar_url)
		msgs[i].content    = resolve_content_urls(server, msgs[i].content)
	}
	return msgs
}

pub fn (c &ZulipClient) fetch_stream_messages(stream_name string, topic string, anchor string) ![]ZulipMessage {
	narrow := '[{"operator":"stream","operand":"${stream_name}"},{"operator":"topic","operand":"${topic}"}]'
	return c.fetch_messages(narrow, 50, 0, anchor)!
}

// fetch_single_message retrieves a single message by id.
// Used to refresh reactions on a message without reloading the whole conversation.
pub fn (c &ZulipClient) fetch_single_message(msg_id int) !ZulipMessage {
	narrow := urllib.path_escape('[{"operator":"id","operand":${msg_id}}]')
	path := '/messages?narrow=${narrow}&num_before=0&num_after=0&anchor=${msg_id}&apply_markdown=false&client_gravatar=false'
	body := c.get(path)!
	resp := json.decode(MessagesResponse, body)!
	if resp.result != 'success' {
		return error('fetch_single_message: ${resp.result}')
	}
	server := c.creds.server_url.trim_right('/')
	mut msgs := resp.messages.clone()
	for i in 0 .. msgs.len {
		msgs[i].avatar_url = resolve_url(server, msgs[i].avatar_url)
		msgs[i].content    = resolve_content_urls(server, msgs[i].content)
	}
	if msgs.len == 0 {
		return error('fetch_single_message: message ${msg_id} not found')
	}
	return msgs[0]
}

// resolve_url turns a server-relative path (e.g. "/avatar/42") into an
// absolute URL.  Already-absolute URLs are returned unchanged. Empty strings
// are returned as-is so callers can still detect "no avatar".
pub fn resolve_url(server_base string, url string) string {
	if url.len == 0 {
		return url
	}
	if url.starts_with('http://') || url.starts_with('https://') {
		return url
	}
	// Relative path — prepend server base
	if url.starts_with('/') {
		return '${server_base}${url}'
	}
	return url
}

// resolve_content_urls rewrites relative Markdown image references inside
// raw message content so that gui.markdown() can fetch them.
// It handles the two common patterns:
//   ![alt](/user_uploads/...)
//   ![alt](/avatar/...)
pub fn resolve_content_urls(server_base string, content string) string {
	if content.len == 0 || server_base.len == 0 {
		return content
	}
	// Fast path: no relative image references at all
	if !content.contains('](/')  {
		return content
	}
	needle := ']('
	mut sb := strings.new_builder(content.len + 64)
	mut i := 0
	for i < content.len {
		// Manual search for "](" followed by "/"
		mut found := -1
		for j := i; j + 2 < content.len; j++ {
			if content[j] == `]` && content[j + 1] == `(` && content[j + 2] == `/` {
				found = j
				break
			}
		}
		if found == -1 {
			sb.write_string(content[i..])
			break
		}
		// Copy up to and including "]("
		sb.write_string(content[i..found + 2])
		// Prepend server base so the "/" stays: server_base + /path
		sb.write_string(server_base)
		i = found + 2 // continue from the '/' so it gets copied next iteration
	}
	_ = needle
	return sb.str()
}

pub fn (c &ZulipClient) send_stream_message(stream string, topic string, content string) !int {
	data := 'type=stream&to=${urllib.query_escape(stream)}&topic=${urllib.query_escape(topic)}&content=${urllib.query_escape(content)}'
	body := c.post('/messages', data)!
	resp := json.decode(SendMessageResponse, body)!
	if resp.result != 'success' {
		return error('send_message: ${resp.msg}')
	}
	return resp.id
}

pub fn (c &ZulipClient) send_direct_message(to_email string, content string) !int {
	to_json := '["${to_email}"]'
	data := 'type=direct&to=${urllib.query_escape(to_json)}&content=${urllib.query_escape(content)}'
	body := c.post('/messages', data)!
	resp := json.decode(SendMessageResponse, body)!
	if resp.result != 'success' {
		return error('send_direct_message: ${resp.msg}')
	}
	return resp.id
}

pub fn (c &ZulipClient) add_reaction(msg_id int, emoji_name string, emoji_code string, reaction_type string) ! {
	data := 'emoji_name=${urllib.query_escape(emoji_name)}&emoji_code=${urllib.query_escape(emoji_code)}&reaction_type=${urllib.query_escape(reaction_type)}'
	body := c.post('/messages/${msg_id}/reactions', data)!
	// Just check result field without a full struct
	if !body.contains('"result":"success"') && !body.contains('"result": "success"') {
		return error('add_reaction failed: ${body}')
	}
}

pub fn (c &ZulipClient) remove_reaction(msg_id int, emoji_name string, emoji_code string, reaction_type string) ! {
	url := '${c.base_url()}/messages/${msg_id}/reactions'
	mut req := http.Request{
		method: .delete
		url:    url
		data:   'emoji_name=${urllib.query_escape(emoji_name)}&emoji_code=${urllib.query_escape(emoji_code)}&reaction_type=${urllib.query_escape(reaction_type)}'
		header: http.new_header_from_map({
			http.CommonHeader.content_type: 'application/x-www-form-urlencoded'
		})
	}
	req.add_header(.authorization, c.auth_header())
	resp := req.do()!
	if resp.status_code != 200 {
		return error('remove_reaction HTTP ${resp.status_code}: ${resp.body}')
	}
}

pub fn (c &ZulipClient) validate_credentials() bool {
	c.fetch_profile() or { return false }
	return true
}

// ---------------------------------------------------------------------------
// Narrow helpers
// ---------------------------------------------------------------------------

pub fn narrow_stream_topic(stream string, topic string) string {
	return '[{"operator":"stream","operand":"${stream}"},{"operator":"topic","operand":"${topic}"}]'
}

pub fn narrow_direct(email string) string {
	return '[{"operator":"dm","operand":"${email}"}]'
}

// UploadResponse is the API response for /api/v1/user_uploads.
struct UploadResponse {
	result string @[json: 'result']
	msg    string @[json: 'msg']
	uri    string @[json: 'uri']
}

// ext_to_mime returns the MIME type for common file extensions.
fn ext_to_mime(ext string) string {
	return match ext.to_lower().trim_left('.') {
		'png'  { 'image/png' }
		'jpg', 'jpeg' { 'image/jpeg' }
		'gif'  { 'image/gif' }
		'webp' { 'image/webp' }
		'svg'  { 'image/svg+xml' }
		'bmp'  { 'image/bmp' }
		'pdf'  { 'application/pdf' }
		'txt'  { 'text/plain' }
		'mp4'  { 'video/mp4' }
		'mp3'  { 'audio/mpeg' }
		else   { 'application/octet-stream' }
	}
}

// upload_file uploads a local file to the Zulip server and returns
// the server-relative URI (e.g. "/user_uploads/2/xx/…/filename.png").
// The caller can insert this into a message as [filename](uri).
pub fn (c &ZulipClient) upload_file(file_path string) !string {
	file_name := os.base(file_path)
	file_data := os.read_bytes(file_path)!

	ext   := os.file_ext(file_name)
	ctype := ext_to_mime(ext)

	// Build a minimal multipart/form-data body by hand.
	// V's net.http does not expose a multipart helper so we do it manually.
	boundary := 'ZulipBoundary${file_data.len}'
	mut body  := strings.new_builder(file_data.len + 256)
	body.write_string('--${boundary}\r\n')
	body.write_string('Content-Disposition: form-data; name="file"; filename="${file_name}"\r\n')
	body.write_string('Content-Type: ${ctype}\r\n')
	body.write_string('\r\n')
	body.write_string(file_data.bytestr())
	body.write_string('\r\n--${boundary}--\r\n')

	url := '${c.base_url()}/user_uploads'
	mut req := http.Request{
		method: .post
		url:    url
		data:   body.str()
		header: http.new_header_from_map({
			http.CommonHeader.content_type: 'multipart/form-data; boundary=${boundary}'
		})
	}
	req.add_header(.authorization, c.auth_header())
	resp := req.do()!
	if resp.status_code != 200 {
		return error('upload_file HTTP ${resp.status_code}: ${resp.body}')
	}
	up := json.decode(UploadResponse, resp.body)!
	if up.result != 'success' {
		return error('upload_file: ${up.msg}')
	}
	return up.uri
}
