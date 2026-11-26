-- luci-app-device-key: per-device SSH key management
--
-- 设计要点：
--   * 不自动生成密钥；只有用户在 LuCI 里点“生成”才会创建。
--   * 私钥只存在于 /tmp/device-key（tmpfs），领取一次后立即删除。
--   * 设备长期只保留公钥（/etc/device-key/pub + authorized_keys）。
--   * 所有写操作都要再次输入 root 密码（用 openssl passwd 校验 /etc/shadow）。

module("luci.controller.device_key", package.seeall)

local http = require "luci.http"
local sys = require "luci.sys"
local nixio = require "nixio"
local i18n = require "luci.i18n"
local dispatcher = require "luci.dispatcher"
local template = require "luci.template"

local _ = i18n.translate

local HELPER = "/usr/sbin/device-key"

local MSG = {
	generated = _("A new key pair was generated. Claim the private key now."),
	claimed   = _("Private key shown once and deleted from the device."),
	revoked   = _("Device key revoked."),
	saved     = _("Authorized keys saved."),
	badpw     = _("Wrong password, nothing changed."),
	nopending = _("No pending private key on this device."),
	badkeys   = _("Could not update authorized_keys."),
}

local function run(arg)
	return sys.exec(string.format("%s %s 2>/dev/null", HELPER, arg)) or ""
end

-- 已安装的包版本：读 apk / opkg 的数据库，取不到就显示 unknown
local function pkgver(pkg)
	local function scan(path, namekey, verkey)
		local f = io.open(path, "r")
		if not f then return nil end
		local name, ver
		for line in f:lines() do
			if line == "" then
				if name == pkg and ver then f:close(); return ver end
				name, ver = nil, nil
			else
				local k, v = line:match("^([%w%-]+):%s*(.+)$")
				if k == namekey then name = v
				elseif k == verkey then ver = v end
			end
		end
		f:close()
		if name == pkg and ver then return ver end
		return nil
	end
	return scan("/lib/apk/db/installed", "P", "V")
		or scan("/usr/lib/opkg/status", "Package", "Version")
		or "unknown"
end

-- 取 dropbear 的实际端口，页面按它拼命令
local function dropbear_port()
	local p = io.popen("uci -q get dropbear.@dropbear[0].Port 2>/dev/null")
	local port = p and (p:read("*l") or "") or ""
	if p then p:close() end
	if port == "" then port = "22" end
	return port
end

local function status()
	local s = {}
	for line in run("status"):gmatch("[^\n]+") do
		local k, v = line:match("^([%w_]+)=(.*)$")
		if k then s[k] = v end
	end
	return s
end

-- 用 openssl passwd 校验 root 密码：密码经 0600 临时文件传给 helper，
-- 不出现在命令行（ps 可见）里，helper 读完立即删除。
local function check_password(pw)
	if not pw or pw == "" then return false end

	local tmp = string.format("/tmp/.dk-pw-%d-%d", os.time(), math.random(1000000))
	local f = nixio.open(tmp, "w", "600")
	if not f then return false end
	f:write(pw)
	f:close()

	local out = sys.exec(string.format("%s checkpw %s 2>/dev/null", HELPER, tmp))
	os.remove(tmp)

	return out:match("^ok") ~= nil
end

local function field(name)
	return http.formvalue(name)
end

-- 返回 msg, revealed
local function handle_post()
	if http.getenv("REQUEST_METHOD") ~= "POST" then
		return nil, nil
	end

	local action = field("action")
	if not action then return nil, nil end

	if not check_password(field("password")) then
		return "badpw", nil
	end

	if action == "gen" then
		run("gen")
		return "generated", nil
	elseif action == "claim" then
		local key = run("claim")
		if key == "" then return "nopending", nil end
		return "claimed", key
	elseif action == "revoke" then
		run("revoke")
		return "revoked", nil
	elseif action == "savekeys" then
		local body = field("keys") or ""
		local p = io.popen(HELPER .. " setkeys >/dev/null 2>&1", "w")
		if not p then return "badkeys", nil end
		p:write(body)
		p:close()
		return "saved", nil
	end
	return nil, nil
end

function index()
	entry({ "admin", "system", "admin", "device_key" }, call("action_page"),
		_("Device SSH Keys"), 3).leaf = true
end

function action_page()
	local msg, revealed = handle_post()
	local st = status()

	template.render("device_key/main", {
		token    = dispatcher.context.authtoken or "",
		msg      = msg,
		msgtext  = msg and MSG[msg] or nil,
		revealed = revealed,
		sshport  = dropbear_port(),
		appver   = pkgver("luci-app-device-key"),
		state    = st.state or "fresh",
		pending  = (st.pending == "1"),
		fingerprint = st.fingerprint or "",
		created  = st.created or "",
		keys     = run("getkeys"),
		nkeys    = st.keys or "0",
		pwauth   = (st.password_auth == "0") and "0" or "1",
	})
end
