class_name GeoFetch
extends RefCounted

## THE OPEN DATA, OVER HTTPS, FROM INSIDE THE APP (at the user's request: a
## planet-wide selector, "keep it inside the app, linux only"): a blocking GET
## (or a byte range of one) on whatever thread asks — the region builder runs
## on its own — retried with a backoff, and kept on disk under
## user://earth-cache so asking again, or for an overlapping square, costs
## nothing. tools/earth_fetch.py's `http`, in GDScript.
##
## A PROXY AND ITS CERTIFICATE where the machine says so (HTTPS_PROXY, and
## SSL_CERT_FILE for an authority to trust besides Godot's own), as a
## corporate network or a sandbox has them; neither is needed anywhere else.

const UA := "fenrir-earth/1.0 (+https://github.com/verdictzero/mewd-engine)"
const CACHE := "user://earth-cache"
## the body of a cached 404, so a missing tile is not asked for again
const MISSING := "FENRIR:MISSING:404"

static var _tls: TLSOptions = null
static var _tls_ready := false
static var _lock := Mutex.new()


## The body at `url` (a Range of it when `length` > 0), or an empty array and
## `ok` false for a 404 or a failure. {"ok": bool, "body": PackedByteArray,
## "code": int}
static func get_url(url: String, start := -1, length := 0, headers: PackedStringArray = [],
		cache := true, tries := 4) -> Dictionary:
	var key := "%s|%d|%d" % [url, start, length]
	var path := _cache_path(key)
	if cache and FileAccess.file_exists(path):
		var body := FileAccess.get_file_as_bytes(path)
		if body.size() == MISSING.length() and body == MISSING.to_ascii_buffer():
			return {"ok": false, "body": PackedByteArray(), "code": 404}
		return {"ok": true, "body": body, "code": 200}
	var h := PackedStringArray(["User-Agent: " + UA, "Accept-Encoding: identity"])
	h.append_array(headers)
	if start >= 0 and length > 0:
		h.append("Range: bytes=%d-%d" % [start, start + length - 1])
	var res := {"ok": false, "body": PackedByteArray(), "code": 0}
	for i in range(tries):
		res = _once(url, h)
		var code: int = res.code
		if res.ok or code == 404 or code == 400 or code == 401 or code == 403:
			break
		OS.delay_msec(mini(1000 * (1 << i), 8000))
	if cache and (res.ok or int(res.code) == 404):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			if res.ok:
				f.store_buffer(res.body)
			else:
				f.store_string(MISSING)
	return res


static func _cache_path(key: String) -> String:
	var h := key.sha1_text()
	return "%s/%s/%s.bin" % [CACHE, h.substr(0, 2), h.substr(2, 20)]


# the TLS options: Godot's own authorities, or the machine's bundle when it
# names one (SSL_CERT_FILE)
static func _tls_options() -> TLSOptions:
	_lock.lock()
	if not _tls_ready:
		_tls_ready = true
		var bundle := OS.get_environment("SSL_CERT_FILE")
		if bundle != "" and FileAccess.file_exists(bundle):
			var cert := X509Certificate.new()
			if cert.load(bundle) == OK:
				_tls = TLSOptions.client(cert)
	var t := _tls
	_lock.unlock()
	return t if t != null else TLSOptions.client()


# one GET, following redirects (three at most)
static func _once(url: String, headers: PackedStringArray, hops := 3) -> Dictionary:
	var m := RegEx.create_from_string("^(https?)://([^/:]+)(?::(\\d+))?(/.*)?$").search(url)
	if m == null:
		return {"ok": false, "body": PackedByteArray(), "code": -1}
	var https := m.get_string(1) == "https"
	var host := m.get_string(2)
	var port := int(m.get_string(3)) if m.get_string(3) != "" else (443 if https else 80)
	var path := m.get_string(4) if m.get_string(4) != "" else "/"
	var c := HTTPClient.new()
	c.read_chunk_size = 1 << 16
	var proxy := OS.get_environment("HTTPS_PROXY" if https else "HTTP_PROXY")
	if proxy == "":
		proxy = OS.get_environment("https_proxy" if https else "http_proxy")
	if proxy != "" and not _no_proxy(host):
		var pm := RegEx.create_from_string("^(?:https?://)?(?:[^@/]*@)?([^/:]+):(\\d+)").search(proxy)
		if pm != null:
			if https:
				c.set_https_proxy(pm.get_string(1), int(pm.get_string(2)))
			else:
				c.set_http_proxy(pm.get_string(1), int(pm.get_string(2)))
	var err := c.connect_to_host(host, port, _tls_options() if https else null)
	if err != OK:
		return {"ok": false, "body": PackedByteArray(), "code": -2}
	var deadline := Time.get_ticks_msec() + 120000
	while c.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		c.poll()
		OS.delay_msec(2)
		if Time.get_ticks_msec() > deadline:
			return {"ok": false, "body": PackedByteArray(), "code": -3}
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "body": PackedByteArray(), "code": -4}
	err = c.request(HTTPClient.METHOD_GET, path, headers)
	if err != OK:
		return {"ok": false, "body": PackedByteArray(), "code": -5}
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		c.poll()
		OS.delay_msec(2)
		if Time.get_ticks_msec() > deadline:
			return {"ok": false, "body": PackedByteArray(), "code": -3}
	if not c.has_response():
		return {"ok": false, "body": PackedByteArray(), "code": -6}
	var code := c.get_response_code()
	if code in [301, 302, 303, 307, 308] and hops > 0:
		var loc := ""
		for line in c.get_response_headers():
			if line.to_lower().begins_with("location:"):
				loc = line.substr(9).strip_edges()
		if loc != "":
			if loc.begins_with("/"):
				loc = "%s://%s%s" % ["https" if https else "http", host, loc]
			return _once(loc, headers, hops - 1)
	var body := PackedByteArray()
	while c.get_status() == HTTPClient.STATUS_BODY:
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.is_empty():
			OS.delay_msec(1)
		else:
			body.append_array(chunk)
		if Time.get_ticks_msec() > deadline:
			return {"ok": false, "body": PackedByteArray(), "code": -3}
	c.close()
	return {"ok": code == 200 or code == 206, "body": body, "code": code}


static func _no_proxy(host: String) -> bool:
	var np := OS.get_environment("NO_PROXY")
	if np == "":
		np = OS.get_environment("no_proxy")
	for e in np.split(",", false):
		e = e.strip_edges()
		if e == "" or e.contains("/"):
			continue
		if host == e or host.ends_with("." + e.trim_prefix(".")):
			return true
	return false
