-- ======================================================
--  KIT : INSTALLATEUR TOUT-EN-UN (serveur complet)
-- ======================================================
-- Pose ce fichier sur un ordinateur NEUF (Advanced conseille,
-- avec un ENDER MODEM) puis lance-le :  install-all
-- Il ecrit TOUS les fichiers du serveur KIT (server.lua, repo/,
-- atm/, admin/, installateurs, README) et redemarre.
-- (Pas de videos : depose tes .nfv dans videos/ si besoin.)
-- AUCUN SECRET dans ce fichier : le mot de passe admin et la
-- cle API V-SMP sont demandes au clavier pendant l'installation.
-- Genere automatiquement : ne pas modifier a la main.

local files = {}
files["admin/cobble/admin.lua"] = [=[
-- PIL Admin : console de gestion du serveur KIT (a distance, par rednet).
-- Reutilise le moteur UI de l'OS (cobble/ui.lua, gfx.lua, net.lua).
-- Interface GRAPHIQUE en cartes (ui.menu). Auto-mise a jour depuis le serveur.
local ROOT = "cobble/"
local ui  = dofile(ROOT .. "ui.lua")
local net = dofile(ROOT .. "net.lua")
local gfx = ui.gfx

-- affichage sur moniteur si present
do
  local mon = peripheral.find("monitor")
  if mon then
    local chosen = 0.5
    for _, s in ipairs({ 2, 1.5, 1, 0.5 }) do
      mon.setTextScale(s)
      local w, h = mon.getSize()
      if w >= 26 and h >= 20 then chosen = s; break end
    end
    mon.setTextScale(chosen)
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
    print("KIT Admin -> moniteur")
    term.redirect(mon)
  end
end

pcall(gfx.applyPalette)

-- rendu de la toile avant chaque attente (Ctrl+T neutralise ; on quitte via "Quitter")
local unpack = table.unpack or unpack
do
  local raw = os.pullEventRaw
  os.pullEvent = function(filter)
    gfx.present()
    while true do
      local e = { raw(filter) }
      if e[1] ~= "terminate" then return unpack(e) end
    end
  end
end

-- ---- connexion ----
ui.clear()
local W, H = ui.size()
gfx.fill(1, 1, W, H, colors.red)
ui.center(math.floor(H / 2), "KIT Admin", colors.white, colors.red)
ui.center(math.floor(H / 2) + 1, "connexion...", colors.white, colors.red)
if not net.open() then
  ui.message("Admin", { "Serveur introuvable.", "Modem + serveur allumes ?" })
  return
end

-- ---- helpers ----
local PASS
local function areq(t, timeout)
  t.pass = PASS
  return net.request(t, timeout or 6)
end

local function login()
  while true do
    local p = ui.input("Mot de passe admin (vide=quitter)", "", { mask = true })
    if not p or p == "" then return false end
    local r = net.request({ action = "admin_auth", pass = p }, 5)
    if r and r.ok then PASS = p; return true end
    ui.message("Admin", { "Mot de passe incorrect." })
  end
end

-- ===================== ECRANS =====================

-- Telephones connectes : push OS (a un ou a tous), message a tous.
local function screenClients()
  while true do
    local r = areq({ action = "admin_clients" })
    if not r then ui.message("Admin", { "Serveur injoignable" }); return end
    local cs = r.clients or {}
    local entries = {
      { label = "Push OS -> tous", sub = "mettre a jour tous les tels", icon = ">", color = colors.green, act = "pushall" },
      { label = "Message a tous",  sub = "diffuser un texte",           icon = "M", color = colors.blue,  act = "msg" },
    }
    for _, c in ipairs(cs) do
      entries[#entries + 1] = { label = c.name, sub = "telephone #" .. c.id,
        icon = tostring(c.name):sub(1, 1):upper(), color = colors.cyan, act = "phone", cid = c.id, cname = c.name }
    end
    local idx = ui.menu("Telephones", entries, { status = #cs .. " en ligne" })
    if idx == "back" then return end
    local e = entries[idx]
    if e.act == "pushall" then
      if ui.confirm("Push", "Envoyer l'OS a jour a TOUS les telephones ?") then
        local rr = areq({ action = "admin_push", target = "all", pkg = "pocketos" })
        ui.message("Push", { "Envoye a " .. tostring(rr and rr.count or 0) .. " tel(s)." })
      end
    elseif e.act == "msg" then
      local t = ui.input("Message a diffuser")
      if t and #t > 0 then
        local rr = areq({ action = "admin_broadcast", text = t })
        ui.message("Message", { "Diffuse a " .. tostring(rr and rr.count or 0) .. " tel(s)." })
      end
    elseif e.act == "phone" then
      local si = ui.menu(e.cname .. " #" .. e.cid, {
        { label = "Push OS a ce tel", sub = "mettre a jour ce telephone", icon = ">", color = colors.green },
      })
      if si ~= "back" then
        local rr = areq({ action = "admin_push", target = tostring(e.cid), pkg = "pocketos" })
        ui.message("Push", { (rr and rr.ok) and "OS envoye." or "Echec." })
      end
    end
  end
end

-- Apps du store : activer / desactiver / supprimer.
local function screenPkgs()
  while true do
    local r = areq({ action = "admin_pkgs" })
    if not r then ui.message("Admin", { "Serveur injoignable" }); return end
    local ps = r.pkgs or {}
    if #ps == 0 then ui.message("Apps", { "Aucun paquet." }); return end
    local entries = {}
    for i, p in ipairs(ps) do
      entries[i] = { label = p.name,
        sub = (p.disabled and "[DESACTIVE]  " or "") .. "v" .. tostring(p.version or "?"),
        icon = tostring(p.name):sub(1, 1):upper(),
        color = p.disabled and colors.gray or colors.magenta,
        folder = p.folder, pname = p.name, disabled = p.disabled }
    end
    local idx = ui.menu("Apps du store", entries, { status = #ps .. " paquet(s)" })
    if idx == "back" then return end
    local p = entries[idx]
    local subE = {
      { label = p.disabled and "Activer" or "Desactiver", sub = "visibilite dans le store",
        icon = "#", color = colors.orange, act = "toggle" },
      { label = "Supprimer", sub = "effacer le paquet du serveur", icon = "X", color = colors.red, act = "del" },
    }
    local si = ui.menu(p.pname, subE)
    if si ~= "back" then
      local act = subE[si].act
      if act == "toggle" then
        local rr = areq({ action = "admin_pkg_toggle", folder = p.folder })
        if not (rr and rr.ok) then ui.message("Admin", { "Echec : " .. tostring(rr and rr.error) }) end
      elseif act == "del" then
        if ui.confirm("Supprimer", "Supprimer le paquet " .. p.pname .. " ?") then
          local rr = areq({ action = "admin_pkg_delete", folder = p.folder })
          if not (rr and rr.ok) then ui.message("Admin", { "Echec : " .. tostring(rr and rr.error) }) end
        end
      end
    end
  end
end

-- Comptes & argent : voir les soldes, crediter / debiter.
local function screenAccounts()
  while true do
    local r = areq({ action = "admin_accounts" })
    if not r then ui.message("Admin", { "Serveur injoignable" }); return end
    local accs = r.accounts or {}
    if #accs == 0 then ui.message("Comptes", { "Aucun compte cree." }); return end
    local entries = {}
    for i, a in ipairs(accs) do
      entries[i] = { label = a.user, sub = a.balance .. " $" .. (a.online and "  -  en ligne" or ""),
        icon = tostring(a.user):sub(1, 1):upper(),
        color = a.online and colors.green or colors.gray, user = a.user }
    end
    local idx = ui.menu("Comptes & argent", entries, { status = #accs .. " compte(s)" })
    if idx == "back" then return end
    local a = entries[idx]
    local amtS = ui.input("Ajuster solde de " .. a.user .. " (+/-)")
    if amtS then
      local delta = math.floor(tonumber(amtS) or 0)
      if delta ~= 0 then
        local rr = areq({ action = "admin_credit", user = a.user, amount = delta })
        if rr and rr.ok then ui.message("Solde", { a.user .. " : " .. tostring(rr.balance) .. " $" })
        else ui.message("Erreur", { (rr and rr.error) or "echec" }) end
      end
    end
  end
end

-- Videos : supprimer les .nfv du serveur.
local function screenVideos()
  while true do
    local r = areq({ action = "admin_videos" })
    if not r then ui.message("Admin", { "Serveur injoignable" }); return end
    local vs = r.videos or {}
    if #vs == 0 then ui.message("Videos", { "Aucune video sur le serveur." }); return end
    local entries = {}
    for i, v in ipairs(vs) do
      entries[i] = { label = v, sub = "toucher pour supprimer", icon = "V", color = colors.orange, vname = v }
    end
    local idx = ui.menu("Videos", entries, { status = #vs .. " video(s)" })
    if idx == "back" then return end
    local v = entries[idx].vname
    if ui.confirm("Supprimer", "Supprimer la video " .. v .. " ?") then
      areq({ action = "admin_video_delete", name = v })
    end
  end
end

-- Journal du serveur (lecture seule).
local function screenLog()
  local r = areq({ action = "admin_log" })
  if not r then ui.message("Admin", { "Serveur injoignable" }); return end
  local ls = r.logs or {}
  if #ls == 0 then ls = { "(journal vide)" } end
  ui.list("Journal serveur", ls)
end

-- Auto-mise a jour : re-telecharge les libs (pocketos) PUIS la console admin,
-- dans le meme ordre que l'installateur, puis redemarre.
local function selfUpdate()
  if not ui.confirm("Mise a jour", "Telecharger la derniere console admin (+ libs) depuis le serveur ?") then return end
  ui.clear(); ui.bar("Mise a jour")
  ui.center(3, "1/2 : libs de l'OS...", colors.white)
  local a = net.request({ action = "install", pkg = "pocketos" }, 12)
  if not (a and a.data and a.data.files) then ui.message("Mise a jour", { "Echec (libs de base)." }); return end
  net.applyFiles(a.data.files)
  ui.center(4, "2/2 : console admin...", colors.white)
  local b = net.request({ action = "admin_app" }, 12)
  if not (b and b.data and b.data.files) then ui.message("Mise a jour", { "Echec (console admin)." }); return end
  net.applyFiles(b.data.files)
  ui.message("Mise a jour", { "Console a jour.", "Redemarrage..." })
  os.reboot()
end

-- ===================== MENU PRINCIPAL =====================
if not login() then ui.clear(); print("Fin admin."); return end

while true do
  local entries = {
    { label = "Telephones",       sub = "connectes au serveur",  icon = "T", color = colors.cyan,      act = "clients" },
    { label = "Apps du store",    sub = "activer / supprimer",   icon = "A", color = colors.magenta,   act = "pkgs" },
    { label = "Comptes & argent", sub = "crediter / debiter",    icon = "$", color = colors.green,     act = "accounts" },
    { label = "Videos",           sub = "gerer les .nfv",        icon = "V", color = colors.orange,    act = "videos" },
    { label = "Journal serveur",  sub = "voir l'activite",       icon = "J", color = colors.lightBlue, act = "log" },
    { label = "Mettre a jour",    sub = "derniere console admin", icon = "U", color = colors.lime,      act = "update" },
    { label = "Quitter",          sub = "fermer la console",     icon = "O", color = colors.red,       act = "quit" },
  }
  local idx = ui.menu("KIT Admin", entries, { back = false, status = "Serveur #" .. tostring(net.server) })
  if type(idx) == "number" then
    local act = entries[idx].act
    if act == "clients" then screenClients()
    elseif act == "pkgs" then screenPkgs()
    elseif act == "accounts" then screenAccounts()
    elseif act == "videos" then screenVideos()
    elseif act == "log" then screenLog()
    elseif act == "update" then selfUpdate()
    elseif act == "quit" then ui.clear(); print("Fin admin."); return end
  end
end
]=]
files["admin/startup.lua"] = [=[
-- PIL Admin (PC) - console de gestion du serveur KIT
-- (remplace le startup.lua de l'OS : demarre en mode admin, pas en mode tel)
if fs.exists("cobble/admin.lua") then
  shell.run("cobble/admin.lua")
else
  print("cobble/admin.lua introuvable")
end
]=]
files["atm/cobble/atm.lua"] = [=[
-- PIL ATM : distributeur de la Banque KIT.
-- Deux modes d'acces :
--  1) TELEPHONE insere dans le LECTEUR DE DISQUE (monte sur /disk,
--     l'ATM lit /disk/secu/id) -> aucun pseudo demande ;
--  2) PSEUDO tape au clavier (bouton sur l'ecran d'accueil) -> session
--     avec deconnexion auto apres 45 s d'inactivite.
-- Le RETRAIT exige le code banque dans les deux cas. Interface graphique.
-- Reutilise le moteur UI de l'OS (cobble/ui.lua, gfx.lua, net.lua).
local ROOT = "cobble/"
local ui  = dofile(ROOT .. "ui.lua")
local net = dofile(ROOT .. "net.lua")
local gfx = ui.gfx

-- affichage sur moniteur (tactile) si present
do
  local mon = peripheral.find("monitor")
  if mon then
    local chosen = 0.5
    for _, s in ipairs({ 2, 1.5, 1, 0.5 }) do
      mon.setTextScale(s)
      local w, h = mon.getSize()
      if w >= 26 and h >= 20 then chosen = s; break end
    end
    mon.setTextScale(chosen)
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
    print("KIT ATM -> moniteur")
    term.redirect(mon)
  end
end

pcall(gfx.applyPalette)

-- rendu de la toile avant chaque attente ; Ctrl+T neutralise (borne verrouillee)
local unpack = table.unpack or unpack
do
  local raw = os.pullEventRaw
  os.pullEvent = function(filter)
    gfx.present()
    while true do
      local e = { raw(filter) }
      if e[1] ~= "terminate" then return unpack(e) end
    end
  end
end

-- ---- lecture de la carte (le telephone insere) ----
local function drives()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "drive" then out[#out + 1] = n end
  end
  return out
end

-- Renvoie la table { uid=, user= } lue sur le tel insere, ou nil.
-- 2e retour : "present" si un disque est la mais sans compte reconnu.
local function readCard()
  local present = false
  for _, d in ipairs(drives()) do
    local ok, has = pcall(peripheral.call, d, "hasData")
    if ok and has then
      present = true
      local okp, mp = pcall(peripheral.call, d, "getMountPath")
      if okp and mp then
        local path = fs.combine(mp, "secu/id")
        if fs.exists(path) then
          local h = fs.open(path, "r"); local data = h.readAll(); h.close()
          local ok2, t = pcall(textutils.unserialise, data)
          if ok2 and type(t) == "table" and t.uid then return t end
          local num = tonumber((data or ""):match("%d+"))
          if num then return { uid = num } end
        end
      end
    end
  end
  return nil, present and "present" or nil
end

-- ---- ecrans ----
local function header(title)
  local W = select(1, term.getSize())
  gfx.fill(1, 1, W, 1, colors.green)
  gfx.text(2, 1, title, colors.white, colors.green)
  gfx.right(W, 1, textutils.formatTime(os.time(), true), colors.white, colors.green)
end

local pseudoBtn
local function drawInsert(warn)
  local W, H = term.getSize()
  gfx.begin(colors.black)
  header("Banque KIT - ATM")
  ui.center(math.floor(H / 2) - 4, "Inserez votre telephone", colors.white)
  ui.center(math.floor(H / 2) - 3, "dans le lecteur de disque", colors.lightGray)
  ui.center(math.floor(H / 2) - 1, "- ou -", colors.gray)
  local lab = " Taper son pseudo "
  local bx = math.floor((W - #lab) / 2) + 1
  local by = math.floor(H / 2) + 1
  gfx.roundRect(bx, by, #lab, 1, colors.blue, colors.black)
  gfx.text(bx, by, lab, colors.white, colors.blue)
  pseudoBtn = { x = bx, y = by, w = #lab, h = 1 }
  if warn then ui.center(by + 2, warn, colors.red) end
  ui.center(H - 1, "Banque KIT", colors.green)
end

local function drawRemove()
  local W, H = term.getSize()
  gfx.begin(colors.black)
  header("Banque KIT - ATM")
  ui.center(math.floor(H / 2), "Merci ! Retirez votre telephone.", colors.yellow)
end

-- Attend un telephone insere OU la saisie d'un pseudo au clavier.
-- Renvoie { uid=, byCard=true } (tel) ou { user= } (pseudo).
local function waitInsert()
  drawInsert()
  while true do
    os.startTimer(1)
    local ev = { os.pullEvent() }
    local card, why = readCard()
    if card then card.byCard = true; return card end
    if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      if ui.hit(pseudoBtn, ev[3], ev[4]) then
        local u = ui.input("Ton pseudo")
        if u and u ~= "" then return { user = u } end
        drawInsert()
      end
    elseif ev[1] == "disk" or ev[1] == "disk_eject" or ev[1] == "timer" then
      drawInsert(why == "present" and "Telephone non reconnu (pas de compte)" or nil)
    end
  end
end

-- Ecran du compte : solde + gros boutons. Surveille l'ejection du tel
-- (mode carte) ou l'inactivite (mode pseudo : deconnexion auto apres 45 s).
local function accountScreen(info, byCard)
  local W, H = term.getSize()
  local btns
  local IDLE_LIMIT = 45
  local lastAct = os.clock()
  local function draw()
    gfx.begin(colors.black)
    header("Banque KIT - ATM")
    ui.center(3, info.user or "compte", colors.white)
    gfx.roundRect(3, 4, W - 4, 1, colors.gray, colors.black, 1)
    gfx.center(math.floor(W / 2), 4, "Solde : " .. info.balance .. " $", colors.lime, colors.gray)
    if (info.feeRate or 0) > 0 then
      ui.center(5, ("Commission %d%% par operation"):format(
        math.floor(info.feeRate * 100 + 0.5)), colors.lightGray)
    end
    btns = {}
    local function big(y, label, color, id)
      gfx.roundRect(3, y, W - 4, 2, color, colors.black, 2)
      gfx.center(math.floor(W / 2), y, label, colors.white, color)
      btns[#btns + 1] = { x = 3, y = y, w = W - 4, h = 2, id = id }
    end
    big(6, "Deposer", colors.green, "deposit")
    big(9, "Retirer", colors.orange, "withdraw")
    big(H - 2, byCard and "Ejecter / Fin" or "Terminer", colors.red, "eject")
  end
  draw()
  while true do
    os.startTimer(1)
    local ev = { os.pullEvent() }
    if ev[1] == "timer" then
      if byCard then
        if not readCard() then return "eject" end
      elseif os.clock() - lastAct > IDLE_LIMIT then
        return "eject"   -- session pseudo abandonnee -> retour accueil
      end
      draw()
    elseif ev[1] == "disk_eject" then
      if byCard then return "eject" end
    elseif ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      lastAct = os.clock()
      for _, b in ipairs(btns) do if ui.hit(b, ev[3], ev[4]) then return b.id end end
    end
  end
end

local function doDeposit(card, info)
  local amtS = ui.keypad("Depot - montant", { hint = "montant" })
  local amt = tonumber(amtS)
  if not amt then return end
  local r = net.request({ action = "atm_deposit", uid = card.uid, user = card.user, amount = amt }, 6)
  if r and r.ok then
    info.balance = r.balance
    local lines = { "Credite : +" .. (r.net or math.floor(amt)) .. " $" }
    if (r.fee or 0) > 0 then lines[#lines + 1] = "Commission : " .. r.fee .. " $" end
    lines[#lines + 1] = "Nouveau solde : " .. r.balance
    ui.message("Depot", lines)
  else ui.message("Depot", { (r and r.error) or "echec" }) end
end

local function doWithdraw(card, info)
  if not info.hasBankPass then
    ui.message("Retrait", { "Aucun code banque defini.", "Retrait impossible.", "Definis-le dans l'app Banque." })
    return
  end
  local code = ui.keypad("Code banque", { mask = true, hint = "code" })
  if not code or code == "" then return end
  local amtS = ui.keypad("Retrait - montant", { hint = "montant" })
  local amt = tonumber(amtS)
  if not amt then return end
  local r = net.request({ action = "atm_withdraw", uid = card.uid, user = card.user, amount = amt, bankpass = code }, 6)
  if r and r.ok then
    info.balance = r.balance
    local lines = { "Remis : " .. (r.net or math.floor(amt)) .. " $" }
    if (r.fee or 0) > 0 then lines[#lines + 1] = "Commission : " .. r.fee .. " $ (debite -" .. math.floor(amt) .. ")" end
    lines[#lines + 1] = "Nouveau solde : " .. r.balance
    ui.message("Retrait", lines)
  else ui.message("Retrait", { (r and r.error) or "echec" }) end
end

local function session(card)
  local info = net.request({ action = "atm_info", uid = card.uid, user = card.user }, 6)
  if not (info and info.ok) then
    ui.message("ATM", { (info and info.error) or "Serveur injoignable" })
    return
  end
  if info.uid then card.uid = info.uid end   -- resolu par pseudo -> memorise l'uid
  while true do
    if card.byCard and not readCard() then return end   -- tel retire
    local act = accountScreen(info, card.byCard)
    if act == "eject" then return
    elseif act == "deposit" then doDeposit(card, info)
    elseif act == "withdraw" then doWithdraw(card, info) end
  end
end

-- ---- boucle principale ----
if not net.open() then
  drawInsert("Serveur KIT introuvable")
end

while true do
  local card = waitInsert()
  session(card)
  -- mode carte : attendre le retrait physique du tel avant de reproposer
  while card.byCard and readCard() do
    drawRemove()
    os.startTimer(1); os.pullEvent()
  end
end
]=]
files["atm/startup.lua"] = [=[
-- PIL ATM (borne) - distributeur de la Banque KIT
-- (remplace le startup.lua : demarre en mode ATM, pas en mode telephone)
while true do
  if fs.exists("cobble/atm.lua") then
    pcall(shell.run, "cobble/atm.lua")
  else
    print("cobble/atm.lua introuvable")
    sleep(2)
  end
  sleep(0.2)
end
]=]
files["diag.lua"] = [=[
-- Diagnostic disque du serveur. A lancer EN JEU : tape  diag
print("== Diagnostic disque ==")
print("Espace libre (/): " .. tostring(fs.getFreeSpace("/")))
if fs.getCapacity then print("Capacite (/): " .. tostring(fs.getCapacity("/"))) end
print("accounts.tbl existe ? " .. tostring(fs.exists("accounts.tbl"))
      .. "  isDir ? " .. tostring(fs.isDir("accounts.tbl")))
print("readOnly(/) ? " .. tostring(fs.isReadOnly("/")))
print("readOnly(accounts.tbl) ? " .. tostring(fs.isReadOnly("accounts.tbl")))

print("-- test d'ecriture --")
local h, err = fs.open("accounts.tbl", "w")
if h then
  h.write("test"); h.close()
  print("ECRITURE OK -> accounts.tbl ecrit.")
  fs.delete("accounts.tbl")
  print("(fichier test supprime)")
else
  print("ECHEC ecriture : " .. tostring(err))
end

-- lecteur de disque eventuel (secours)
local drv = peripheral.find("drive")
if drv then
  local mp = drv.getMountPath and drv.getMountPath() or nil
  print("Disk drive present, mount = " .. tostring(mp))
else
  print("Aucun disk drive attache.")
end
]=]
files["gfx.lua"] = [=[
-- CobbleNet : bibliotheque graphique partagee (tel + serveur/moniteur)
-- Dessine sur le terminal courant (utiliser term.redirect pour un moniteur).
local gfx = {}

-- Palette "flat design" (appliquee sur les ecrans Advanced)
gfx.palette = {
  [colors.white]     = 0xf5f6fa,
  [colors.orange]    = 0xe67e22,
  [colors.magenta]   = 0xe84393,
  [colors.lightBlue] = 0x54a0ff,
  [colors.yellow]    = 0xfeca57,
  [colors.lime]      = 0x4cd137,
  [colors.pink]      = 0xff9ff3,
  [colors.gray]      = 0x2f3640,
  [colors.lightGray] = 0x8395a7,
  [colors.cyan]      = 0x00d2d3,
  [colors.purple]    = 0x9b59b6,
  [colors.blue]      = 0x3742fa,
  [colors.brown]     = 0x795548,
  [colors.green]     = 0x27ae60,
  [colors.red]       = 0xee5253,
  [colors.black]     = 0x1e272e,
}

function gfx.applyPalette(t)
  t = t or term
  if not t.setPaletteColour then return end
  for c, hex in pairs(gfx.palette) do pcall(t.setPaletteColour, c, hex) end
end

-- correspondance caractere blit -> couleur
local BLIT = {}
local HEX = "0123456789abcdef"
for i = 0, 15 do BLIT[HEX:sub(i + 1, i + 1)] = 2 ^ i end
gfx.BLIT = BLIT

function gfx.fill(x, y, w, h, color)
  term.setBackgroundColor(color)
  local s = string.rep(" ", math.max(0, w))
  for i = 0, h - 1 do
    term.setCursorPos(x, y + i)
    term.write(s)
  end
end

-- Rectangle a coins "arrondis" (les 4 coins prennent la couleur de fond)
function gfx.roundRect(x, y, w, h, color, bg)
  gfx.fill(x, y, w, h, color)
  if bg and w >= 2 and h >= 2 then
    term.setBackgroundColor(bg)
    term.setCursorPos(x, y);             term.write(" ")
    term.setCursorPos(x + w - 1, y);     term.write(" ")
    term.setCursorPos(x, y + h - 1);     term.write(" ")
    term.setCursorPos(x + w - 1, y + h - 1); term.write(" ")
  end
end

-- Contour (pour l'effet "selectionne"), sans toucher les coins
function gfx.outline(x, y, w, h, color)
  term.setBackgroundColor(color)
  term.setCursorPos(x + 1, y);         term.write(string.rep(" ", math.max(0, w - 2)))
  term.setCursorPos(x + 1, y + h - 1); term.write(string.rep(" ", math.max(0, w - 2)))
  for i = 1, h - 2 do
    term.setCursorPos(x, y + i);         term.write(" ")
    term.setCursorPos(x + w - 1, y + i); term.write(" ")
  end
end

function gfx.text(x, y, s, fg, bg)
  if bg then term.setBackgroundColor(bg) end
  if fg then term.setTextColor(fg) end
  term.setCursorPos(x, y)
  term.write(tostring(s))
end

function gfx.center(cx, y, s, fg, bg)
  gfx.text(cx - math.floor(#tostring(s) / 2), y, s, fg, bg)
end

function gfx.right(rx, y, s, fg, bg)
  s = tostring(s)
  gfx.text(rx - #s + 1, y, s, fg, bg)
end

-- Dessine une image (matrice de caracteres blit ; ' ' = transparent)
function gfx.drawArt(x, y, art)
  for r = 1, #art do
    local row = art[r]
    for c = 1, #row do
      local ch = row:sub(c, c)
      local col = BLIT[ch]
      if col then
        term.setBackgroundColor(col)
        term.setCursorPos(x + c - 1, y + r - 1)
        term.write(" ")
      end
    end
  end
end

-- Charge une image .nfp (paintutils) si elle existe, sinon nil
function gfx.loadNFP(path)
  if fs.exists(path) and paintutils and paintutils.loadImage then
    local ok, img = pcall(paintutils.loadImage, path)
    if ok then return img end
  end
  return nil
end

function gfx.drawNFP(img, x, y)
  if img and paintutils and paintutils.drawImage then
    paintutils.drawImage(img, x, y)
  end
end

function gfx.hit(b, mx, my)
  return b ~= nil and mx >= b.x and mx < b.x + b.w and my >= b.y and my < b.y + b.h
end

function gfx.wrap(str, width)
  str = tostring(str)
  local out = {}
  while #str > width do out[#out + 1] = str:sub(1, width); str = str:sub(width + 1) end
  out[#out + 1] = str
  return out
end

return gfx
]=]
files["install-atm.lua"] = [=[
-- PIL ATM : installateur pour la BORNE (distributeur).
-- Materiel : un ORDINATEUR (Advanced conseille pour le tactile) + un MODEM
-- (pour joindre le serveur) + un LECTEUR DE DISQUE (ou l'on insere le tel).
-- A copier sur l'ordinateur (edit install / Ctrl+V / run install). Une fois.
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n) == "modem" then rednet.open(n) end
end
print("Recherche du serveur KIT...")
local s = rednet.lookup("cobblenet", "server")
if not s then
  print("Serveur introuvable. Modem + serveur (PC) allumes ?")
  return
end

local function fetch(msg)
  rednet.send(s, msg, "cobblenet")
  local _, r = rednet.receive("cobblenet", 12)
  return r
end
local function writeFiles(files)
  local n = 0
  for path, content in pairs(files) do
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(path, "w"); h.write(content); h.close(); n = n + 1
  end
  return n
end

print("1/2 : libs de l'OS...")
local a = fetch({ action = "install", pkg = "pocketos" })
if not (a and a.data and a.data.files) then print("Echec (libs de base)."); return end
writeFiles(a.data.files)

print("2/2 : borne ATM...")
local b = fetch({ action = "atm_app" })
if not (b and b.data and b.data.files) then print("Echec (ATM)."); return end
writeFiles(b.data.files)

if #({ peripheral.find("drive") }) == 0 then
  print("ATTENTION : aucun lecteur de disque detecte.")
  print("Attaches-en un avant d'utiliser la borne.")
end

print("Installe. Redemarrage sur la borne ATM...")
sleep(1)
os.reboot()
]=]
files["install-pc-admin.lua"] = [=[
-- PIL Admin : installateur pour ORDINATEUR (console de gestion du serveur KIT).
-- A copier sur un PC (edit install / Ctrl+V / run install). A lancer une fois.
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n) == "modem" then rednet.open(n) end
end
print("Recherche du serveur KIT...")
local s = rednet.lookup("cobblenet", "server")
if not s then
  print("Serveur introuvable. Modem + serveur (PC) allumes ?")
  return
end

local function fetch(msg)
  rednet.send(s, msg, "cobblenet")
  local _, r = rednet.receive("cobblenet", 12)
  return r
end
local function writeFiles(files)
  local n = 0
  for path, content in pairs(files) do
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(path, "w"); h.write(content); h.close(); n = n + 1
  end
  return n
end

print("1/2 : OS de base...")
local a = fetch({ action = "install", pkg = "pocketos" })
if not (a and a.data and a.data.files) then print("Echec (OS de base)."); return end
writeFiles(a.data.files)

print("2/2 : console admin...")
local b = fetch({ action = "admin_app" })
if not (b and b.data and b.data.files) then print("Echec (console admin)."); return end
writeFiles(b.data.files)

print("Installe. Redemarrage sur la console admin...")
sleep(1)
os.reboot()
]=]
files["install-phone.lua"] = [=[
-- CobblePhone : installateur.
-- A COPIER SUR LE TELEPHONE (voir README). A lancer une seule fois.
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n) == "modem" then rednet.open(n) end
end
print("Recherche du serveur KIT...")
local s = rednet.lookup("cobblenet", "server")
if not s then
  print("Serveur introuvable. Verifie que le PC 7 tourne")
  print("et que ce telephone a un Ender Modem.")
  return
end
rednet.send(s, { action = "install", pkg = "pocketos" }, "cobblenet")
local _, r = rednet.receive("cobblenet", 10)
if r and r.data and r.data.files then
  local n = 0
  for path, content in pairs(r.data.files) do
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(path, "w"); h.write(content); h.close()
    n = n + 1
  end
  print("OS installe (" .. n .. " fichiers). Redemarrage...")
  sleep(1)
  os.reboot()
else
  print("Echec du telechargement.")
end
]=]
files["README.txt"] = [=[
======================================================
 KIT (serveur PC 7) + OS de poche PIL   [ex CobbleNet/CobblePhone]
======================================================

PROTOCOLE : rednet "cobblenet"   /   hote : "server"

--- LE SERVEUR (ce PC, id 7) ---
1. Attache un ENDER MODEM sur le PC (portee infinie).
2. (Option) Colle un ou plusieurs MONITEURS (Advanced Monitor pour la
   couleur) contre le PC, ou relie-les par cable reseau + modem cable.
3. Reboot : startup.lua lance server.lua automatiquement.
   - Ecran du PC = journal + touches P (push) / Q (quitter).
   - Moniteur = DASHBOARD TACTILE : paquets, telephones en ligne, journal,
     et boutons cliquables "Push OS" (par tel) et "Push OS -> tous".
   Le fichier gfx.lua (a cote de server.lua) est requis (bibliotheque UI).

--- LE DEPOT repo/ ---
Chaque sous-dossier de repo/ = un paquet installable :
  repo/<nom>/package.info   -> { name=, desc=, version= }
  repo/<nom>/files/...      -> copie telle quelle sur le telephone
Paquets fournis : pocketos (l'OS), horloge, calculatrice.
Pour ajouter une app : cree repo/<nom>/files/cobble/apps/<app>.lua
(1re ligne "-- @name Mon Appli") et un package.info. Rien d'autre.
Paquets fournis aussi : 2048, snake, youcube.

DESACTIVER un paquet : renomme son dossier avec ".dis" a la fin
  repo/youcube  ->  repo/youcube.dis
Il disparait du Magasin et devient non-installable. Enleve ".dis" pour
le reactiver. (Necessite un redemarrage du serveur.)

--- CONSOLE ADMIN (gestion a distance du serveur) ---
Installe-la sur un ORDINATEUR (avec un modem pour joindre le serveur, et
un moniteur optionnel) :
  1) edit install   2) Ctrl+V le contenu de install-pc-admin.lua
  3) Ctrl+S, Ctrl+E   4) tape : install
Le PC redemarre sur la console admin (fond rouge "KIT Admin").
Mot de passe par defaut : "kit"  (change ADMIN_PASS en haut de server.lua).
Permet : voir les telephones + push OS / message a tous, activer/desactiver
/supprimer des apps du store, COMPTES & ARGENT (crediter/debiter un compte),
lister/supprimer des videos, voir le journal.
Interface GRAPHIQUE en cartes (comme le telephone). Menu "Mettre a jour" =
la console se re-telecharge elle-meme depuis le serveur (libs + admin) et
redemarre : plus besoin de refaire l'installateur a chaque changement.
  -> La 1re fois seulement (migration), refais l'installateur une fois pour
     recuperer la console graphique ; ensuite "Mettre a jour" suffit.
Les fichiers admin sont dans le dossier admin/ (servi par l'action admin_app).
Modif de server.lua -> REDEMARRE le serveur pour activer les actions admin.

NOTE SAISIE : le clavier tactile a l'ecran a ete retire ; on tape au CLAVIER
PHYSIQUE (Entree = valider, fleche "<" ou clic Retour = annuler). Un moniteur
sans clavier ne peut donc plus saisir de texte (OK pour un pocket/PC).

--- INSTALLER L'OS SUR UN TELEPHONE ---
Telephone = Advanced Pocket Computer + Ender Modem.
Sur le telephone :
  1) edit install
  2) Ctrl+V  (colle le contenu de install-phone.lua)
  3) Ctrl+S puis Ctrl+E pour sortir
  4) tape : install
L'OS se telecharge depuis le serveur et le telephone redemarre dessus.

--- POUSSER (PUSH) DEPUIS LE SERVEUR ---
Marche seulement vers un telephone qui a DEJA l'OS (il ecoute en fond).
Un tel tout neuf doit d'abord faire l'install ci-dessus une fois.
Sur l'ecran du serveur :
  P  -> tape l'id du tel (visible en vert en haut) ou 'all'
        puis le nom du paquet (vide = pocketos).
Le(s) telephone(s) recoivent les fichiers ; si c'est 'pocketos' ils
redemarrent tout seuls sur la nouvelle version.
(Cote tel : Reglages > Mettre a jour = la meme chose en mode "get".)

--- UTILISER L'OS (interface graphique v3) ---
Accueil facon telephone : grille de TUILES carrees a coins arrondis, avec
une petite ICONE-image et le nom. CLIQUE une tuile pour ouvrir l'app ;
fleche "<" en haut a gauche = retour ; "Eteindre" en bas a droite ;
si >4 apps, boutons "< >" pour changer de page.
La SOURIS marche uniquement sur un ADVANCED Pocket Computer (dore).
Fallback clavier partout : fleches = naviguer (tuile en surbrillance),
Entree = ouvrir, Q/Retour arriere = retour. Saisie de texte = vrai clavier.

NOTE "hover" : un terminal/moniteur CC ne recoit PAS le survol de souris
(pas d'event mouse_move), seulement les CLICS. Le survol est donc remplace
par la surbrillance de la tuile selectionnee + une animation d'appui.

Couleurs : palette riche appliquee sur les ecrans Advanced (degrade en
niveaux de gris sur les non-Advanced).

RESOLUTION : la grille texte du pocket est figee a 26x20 (pas de zoom
possible, contrairement aux moniteurs). Le graphisme (tuiles, coins
arrondis, icones) est dessine en SOUS-PIXELS -> toile de 52x60 pixels
(2x3 par cellule) via cobble/gfx.lua. Le texte reste en police systeme
(plus lisible qu'une pixel-font). Un caractere sous-pixel = 2 couleurs max.

ICONES personnalisees (images) : pose un fichier peint
  cobble/icons/<nom-app>.nfp   (ex: cobble/icons/store.nfp)
sur le tel -> il remplace l'icone integree. Cree-le avec la commande
"paint <fichier>" en jeu. Sinon les icones pixel-art integrees sont
utilisees.
Logo PIL (dessine en sous-pixels) affiche au demarrage.
Apps : Magasin, Chat, Reglages (nom, MAJ OS, etat, reconnexion).
Store : Horloge, Calculatrice (tactile, boutons + fleche retour).
Chaque app a une fleche "<" (haut-gauche) OU la touche Q pour revenir
a l'accueil.

--- VERROUILLAGE (l'utilisateur n'a pas acces au code) ---
- L'OS se lance seul au boot (startup.lua) et tourne en mode kiosque.
- Ctrl+T (terminate) est neutralise : impossible de sortir vers le shell.
- "Eteindre" coupe reellement le tel (os.shutdown), pas de retour au shell.
- L'app Fichiers a ete retiree (elle laissait voir/executer le code).
- La calculatrice est en bac a sable (pas d'acces a fs/os).
Limite honnete : quelqu'un qui ouvre les FICHIERS DU MONDE sur le PC
(dossier computercraft/computer/<id>) peut toujours lire le code -- ca,
aucun programme in-game ne peut l'empecher. En jeu, via le telephone,
il n'y a plus d'acces au code.

--- COMPTES + BANQUE (v2) ---
TOUTES les donnees utilisateur sont maintenant sur le SERVEUR (fichier
accounts.tbl). Le telephone ne stocke qu'un jeton de session (cobble/session.tbl).

Au 1er demarrage, le tel affiche un ecran CONNEXION :
  - "Creer un compte" : pseudo (min 3, lettres/chiffres) + mot de passe.
  - "Se connecter"    : pseudo + mot de passe d'un compte existant.
Chaque compte a un UID unique. Un compte ne peut etre connecte que sur UN
SEUL telephone a la fois : si tu te connectes ailleurs pendant qu'une session
est active, le serveur REFUSE ("compte deja connecte"). La session est liberee
apres ~30 s sans signe de vie (heartbeat) du telephone, ou via
Reglages > Se deconnecter. Ensuite l'auto-login reconnecte tout seul au reboot.

APP BANQUE (pre-installee) : voir son solde, definir/changer un CODE BANQUE
(demande a l'ouverture de l'app), et envoyer de l'argent a un autre pseudo.
L'argent est 100% cote serveur (impossible a trafiquer depuis le tel).

CREDITER / DEBITER un compte depuis le SERVEUR :
  Sur l'ecran du serveur, touche  C  -> tape le pseudo puis le montant
  (positif = credit, negatif = debit). Le solde du joueur se met a jour en direct.
La console admin peut aussi utiliser les actions admin_accounts / admin_credit
(protegees par ADMIN_PASS).

Le CHAT est aussi global et persistant cote serveur (chat.tbl).

--- COMMISSION PIL (integration V-SMP) ---
Chaque transaction d'argent (transfert entre joueurs, depot ATM, retrait
ATM) est taxee : TAX_RATE (2% par defaut, en haut de server.lua) est
preleve SUR LE MONTANT et credite a l'entreprise TAX_ENTERPRISE ("PIL")
via l'API web V-SMP (/enterprise/deposit, la meme API que le
ServeurCentral V-SMP). Les credits admin (touche C / console) ne sont
PAS taxes.
  - Transfert : l'envoyeur paye le montant, le destinataire recoit
    montant - commission.
  - Depot ATM : le compte est credite de montant - commission.
  - Retrait ATM : le compte est debite du montant, le joueur "recoit"
    montant - commission.
L'envoi a l'API est NON bloquant : si le site est injoignable, les
commissions s'accumulent dans fees.tbl et sont renvoyees automatiquement
(nouvel essai toutes les ~30 s ; un refus applicatif est retente 5 fois
puis abandonne, voir le journal). Le total preleve et la file d'attente
s'affichent sur l'ecran du serveur et le dashboard moniteur.
NOTE : le pseudo du compte KIT est envoye comme "username" a l'API ;
il doit correspondre a un pseudo connu du site V-SMP.
NECESSITE l'API http de ComputerCraft activee (config par defaut : oui).

--- BORNE ATM (distributeur) ---
Machine ou l'on DEPOSE / RETIRE de l'argent. Deux modes d'acces :
  1) inserer son TELEPHONE dans le lecteur (aucun pseudo demande) ;
  2) bouton "Taper son pseudo" sur l'ecran d'accueil (clavier PHYSIQUE
     requis) -> session avec deconnexion auto apres 45 s d'inactivite,
     bouton "Terminer" pour fermer. Le retrait exige toujours le CODE
     BANQUE ; voir son solde et deposer sont possibles sans code.
Materiel de la borne :
  - un ORDINATEUR (Advanced conseille : ecran tactile) ;
  - un MODEM (pour joindre le serveur) ;
  - un LECTEUR DE DISQUE colle a l'ordinateur (on y met le tel).
Installation : sur l'ordinateur -> edit install -> Ctrl+V du contenu de
install-atm.lua -> Ctrl+S, Ctrl+E -> tape : install. La borne demarre.

Comment ca marche :
  - Le TELEPHONE ecrit son identifiant de compte dans /secu/id (a la
    connexion / creation de compte). Insere dans le lecteur, le tel est monte
    sur /disk -> la borne lit /disk/secu/id et reconnait le compte.
  - Elle affiche le solde et propose DEPOSER / RETIRER (pave tactile).
  - DEPOT = ajoute au solde (pas de code demande).
  - RETRAIT = demande le CODE BANQUE (defini dans l'app Banque du tel) puis
    le montant. PAS DE CODE BANQUE DEFINI => RETRAIT IMPOSSIBLE.
  - Modele actuel "solde seul" (nombres) ; passage a une monnaie-objet
    physique (coffre) possible plus tard.
IMPORTANT : mets un code banque NUMERIQUE (le pave de la borne est a chiffres).
Le solde du tel se met a jour en direct s'il est connecte.

--- METTRE A JOUR UN TEL DEJA INSTALLE ---
Sur le tel : Reglages > Mettre a jour l'OS (recupere la derniere version
du serveur). Ou depuis le serveur : touche P > id du tel > pocketos.
]=]
files["repo/2048/files/cobble/apps/2048.lua"] = [=[
-- @name 2048
-- Le jeu 2048. Fleches OU boutons tactiles. Meilleur score persistant.
return function(sys)
  local ui = sys.ui
  local gfx = ui.gfx
  math.randomseed((os.epoch and os.epoch("utc")) or os.time())

  local BEST = "cobble/2048.best"
  local function loadBest()
    if fs.exists(BEST) then
      local h = fs.open(BEST, "r"); local n = tonumber(h.readAll()); h.close()
      return n or 0
    end
    return 0
  end
  local function saveBest(n)
    local h = fs.open(BEST, "w"); h.write(tostring(n)); h.close()
  end

  local board, score, best, won = {}, 0, loadBest(), false

  -- ---- couleurs des tuiles ----
  local COLS = {
    [0] = colors.gray, [2] = colors.white, [4] = colors.lightGray,
    [8] = colors.orange, [16] = colors.orange, [32] = colors.red, [64] = colors.red,
    [128] = colors.yellow, [256] = colors.yellow, [512] = colors.lime,
    [1024] = colors.green, [2048] = colors.cyan,
  }
  local function tileColor(v) return COLS[v] or colors.magenta end
  local function textColor(v)
    if v == 0 then return colors.gray end
    if v <= 4 then return colors.black end
    return colors.white
  end

  -- ---- logique ----
  local function addRandom()
    local empty = {}
    for r = 1, 4 do for c = 1, 4 do if board[r][c] == 0 then empty[#empty + 1] = { r, c } end end end
    if #empty == 0 then return end
    local p = empty[math.random(#empty)]
    board[p[1]][p[2]] = (math.random(10) == 1) and 4 or 2
  end

  local function reset()
    board = {}
    for r = 1, 4 do board[r] = { 0, 0, 0, 0 } end
    score, won = 0, false
    addRandom(); addRandom()
  end

  local function slide(line)  -- glisse vers le debut, fusionne
    local t = {}
    for _, v in ipairs(line) do if v ~= 0 then t[#t + 1] = v end end
    local res, gained, i = {}, 0, 1
    while i <= #t do
      if t[i + 1] == t[i] then
        res[#res + 1] = t[i] * 2; gained = gained + t[i] * 2; i = i + 2
      else
        res[#res + 1] = t[i]; i = i + 1
      end
    end
    while #res < 4 do res[#res + 1] = 0 end
    return res, gained
  end

  local function move(dir)
    local moved = false
    for k = 1, 4 do
      local cells = {}
      for j = 1, 4 do
        local r, c
        if dir == "left" then r, c = k, j
        elseif dir == "right" then r, c = k, 5 - j
        elseif dir == "up" then r, c = j, k
        else r, c = 5 - j, k end
        cells[j] = { r, c }
      end
      local line = {}
      for j = 1, 4 do line[j] = board[cells[j][1]][cells[j][2]] end
      local res, gained = slide(line)
      score = score + gained
      for j = 1, 4 do
        local rc = cells[j]
        if board[rc[1]][rc[2]] ~= res[j] then moved = true end
        board[rc[1]][rc[2]] = res[j]
      end
    end
    return moved
  end

  local function canMove()
    for r = 1, 4 do
      for c = 1, 4 do
        if board[r][c] == 0 then return true end
        if c < 4 and board[r][c] == board[r][c + 1] then return true end
        if r < 4 and board[r][c] == board[r + 1][c] then return true end
      end
    end
    return false
  end

  -- ---- affichage ----
  local xs = { 1, 7, 13, 19 }
  local ys = { 3, 6, 9, 12 }
  local back, btns

  local function drawBtn(x, y, w, h, lab, col, id)
    gfx.roundRect(x, y, w, h, col, colors.black, 2)
    gfx.center(x + math.floor(w / 2), y + math.floor((h - 1) / 2), lab, colors.white, col)
    btns[#btns + 1] = { x = x, y = y, w = w, h = h, id = id }
  end

  local function draw()
    local W = ui.size()
    ui.clear()
    back = ui.bar("2048", true)
    gfx.text(2, 2, "Score:" .. score, colors.white, colors.black)
    gfx.right(W, 2, "Best:" .. best, colors.lightGray, colors.black)
    for r = 1, 4 do
      for c = 1, 4 do
        local x, y, v = xs[c], ys[r], board[r][c]
        gfx.roundRect(x, y, 6, 3, tileColor(v), colors.black, 2)
        if v > 0 then gfx.center(x + 3, y + 1, tostring(v), textColor(v), tileColor(v)) end
      end
    end
    btns = {}
    drawBtn(10, 15, 7, 2, "^", colors.blue, "up")
    drawBtn(1, 17, 7, 2, "<", colors.blue, "left")
    drawBtn(10, 17, 7, 2, "v", colors.blue, "down")
    drawBtn(19, 17, 7, 2, ">", colors.blue, "right")
    drawBtn(1, 19, 16, 2, "Nouvelle partie", colors.green, "new")
  end

  local function doMove(dir)
    if move(dir) then
      addRandom()
      if score > best then best = score; saveBest(best) end
      draw()
      if not won then
        for r = 1, 4 do for c = 1, 4 do if board[r][c] >= 2048 then won = true end end end
        if won then ui.message("2048", { "Gagne ! Score: " .. score, "Tu peux continuer." }) end
      end
      if not canMove() then
        ui.message("2048", { "Perdu ! Score final: " .. score, "Nouvelle partie..." })
        reset(); draw()
      end
    end
  end

  reset()
  draw()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      if ui.hit(back, ev[3], ev[4]) then return end
      for _, b in ipairs(btns) do
        if ui.hit(b, ev[3], ev[4]) then
          if b.id == "new" then reset(); draw() else doMove(b.id) end
          break
        end
      end
    elseif ev[1] == "key" then
      local k = ev[2]
      if k == keys.up then doMove("up")
      elseif k == keys.down then doMove("down")
      elseif k == keys.left then doMove("left")
      elseif k == keys.right then doMove("right")
      elseif k == keys.n then reset(); draw()
      elseif k == keys.q or k == keys.backspace then return end
    end
  end
end
]=]
files["repo/2048/package.info"] = [=[
{
  name = "2048",
  desc = "Le jeu 2048 : glisse et fusionne les tuiles pour atteindre 2048. Fleches ou boutons tactiles.",
  version = "1.0",
}
]=]
files["repo/calculatrice/files/cobble/apps/calculatrice.lua"] = [=[
-- @name Calculatrice
-- Calculatrice tactile + MEMOIRE : historique persistant (cobble/calc.log).
-- Bouton "H" = historique (clic sur une ligne = la rappeler). Fleche "<" = accueil.
return function(sys)
  local ui = sys.ui
  local gfx = ui.gfx
  local expr, msg = "", ""
  local LOG = "cobble/calc.log"

  local function loadHist()
    if fs.exists(LOG) then
      local h = fs.open(LOG, "r")
      local ok, t = pcall(textutils.unserialise, h.readAll())
      h.close()
      if ok and type(t) == "table" then return t end
    end
    return {}
  end
  local function saveHist(hist)
    while #hist > 30 do table.remove(hist, 1) end
    local h = fs.open(LOG, "w")
    h.write(textutils.serialise(hist))
    h.close()
  end
  local hist = loadHist()

  -- clavier : 4 rangees principales + 1 rangee du bas (5 touches)
  local rows4 = {
    { "7", "8", "9", "/" },
    { "4", "5", "6", "*" },
    { "1", "2", "3", "-" },
    { "0", ".", "=", "+" },
  }
  local xs4 = { 1, 7, 13, 19 }
  local ys4 = { 5, 8, 11, 14 }
  local bottom = { "C", "DEL", "(", ")", "H" }
  local xs5 = { 1, 6, 11, 16, 21 }
  local back, hits

  local function keyColor(lab)
    if lab == "=" then return colors.green
    elseif lab == "C" or lab == "DEL" then return colors.red
    elseif lab == "H" then return colors.blue
    elseif lab:match("[%+%-%*/%(%)]") then return colors.orange end
    return colors.lightGray
  end

  local function draw()
    local W = ui.size()
    ui.clear()
    back = ui.bar("Calculatrice", true)
    gfx.roundRect(1, 2, W, 3, colors.gray, colors.black, 2)
    local shown = (expr == "") and "0" or expr
    gfx.right(W - 1, 3, shown:sub(-(W - 2)), colors.white, colors.gray)
    if msg ~= "" then gfx.text(2, 2, msg:sub(1, W - 2), colors.red, colors.gray) end
    hits = {}
    for r, row in ipairs(rows4) do
      for c, lab in ipairs(row) do
        local x, y, col = xs4[c], ys4[r], keyColor(lab)
        gfx.roundRect(x, y, 5, 3, col, colors.black, 2)
        gfx.center(x + 2, y + 1, lab, colors.white, col)
        hits[#hits + 1] = { x = x, y = y, w = 5, h = 3, lab = lab }
      end
    end
    for c, lab in ipairs(bottom) do
      local x, col = xs5[c], keyColor(lab)
      gfx.roundRect(x, 17, 4, 3, col, colors.black, 2)
      gfx.center(x + 2, 18, lab, colors.white, col)
      hits[#hits + 1] = { x = x, y = 17, w = 4, h = 3, lab = lab }
    end
  end

  local function openHist()
    if #hist == 0 then ui.message("Historique", { "(vide)" }); return end
    local labels = {}
    for i = #hist, 1, -1 do labels[#labels + 1] = hist[i] end
    local kind, i = ui.list("Historique (memoire)", labels)
    if kind == "item" then
      local res = labels[i]:match("=%s*(.+)$")
      if res then expr = res end
    end
  end

  local function apply(lab)
    msg = ""
    if lab == "C" then
      expr = ""
    elseif lab == "DEL" then
      expr = expr:sub(1, #expr - 1)
    elseif lab == "H" then
      openHist()
    elseif lab == "=" then
      if expr == "" then return end
      local fn = load("return " .. expr, "calc", "t", { math = math })
      if fn then
        local ok, res = pcall(fn)
        if ok and res ~= nil then
          hist[#hist + 1] = expr .. " = " .. tostring(res)
          saveHist(hist)
          expr = tostring(res)
        else
          msg = "erreur"
        end
      else
        msg = "expression invalide"
      end
    else
      expr = expr .. lab
    end
  end

  draw()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      if ui.hit(back, ev[3], ev[4]) then return end
      for _, b in ipairs(hits) do
        if ui.hit(b, ev[3], ev[4]) then apply(b.lab); draw(); break end
      end
    elseif ev[1] == "char" then
      local ch = ev[2]
      if ch == "=" then apply("="); draw()
      elseif ch:match("[0-9%.%+%-%*/%(%)]") then expr = expr .. ch; msg = ""; draw() end
    elseif ev[1] == "key" then
      local k = ev[2]
      if k == keys.enter then apply("="); draw()
      elseif k == keys.backspace then apply("DEL"); draw()
      elseif k == keys.q then return end
    end
  end
end
]=]
files["repo/calculatrice/package.info"] = [=[
{
  name = "calculatrice",
  desc = "Calculatrice tactile avec memoire (historique) et fleche retour.",
  version = "2.1",
}
]=]
files["repo/horloge.dis/files/cobble/apps/horloge.lua"] = [=[
-- @name Horloge
return function(sys)
  local ui = sys.ui
  while true do
    local W, H = ui.size()
    ui.clear()
    local back = ui.bar("Horloge", true)
    ui.center(math.floor(H / 2), textutils.formatTime(os.time(), true), colors.white)
    ui.center(math.floor(H / 2) + 1, "Jour " .. os.day(), colors.lightGray)
    ui.fill(1, H, W, 1, colors.gray)
    ui.text(1, H, " Retour ", colors.white, colors.gray)
    os.startTimer(0.5)
    local ev = { os.pullEvent() }
    if (ev[1] == "mouse_click" or ev[1] == "monitor_touch")
        and (ui.hit(back, ev[3], ev[4]) or ev[4] == H) then
      return
    elseif ev[1] == "key" and (ev[2] == keys.q or ev[2] == keys.backspace) then
      return
    end
  end
end
]=]
files["repo/horloge.dis/package.info"] = [=[
{
  name = "horloge",
  desc = "Une horloge plein ecran pour ton telephone.",
  version = "1.1",
}
]=]
files["repo/Lecteur mp6.dis/files/cobble/apps/youcube.lua"] = [=[
-- @name YouCube
-- Lecteur video : recupere les .nfv du serveur (dossier videos/) et les
-- joue en pixels. Format .nfv : "fps w h nframes" puis nframes*h lignes
-- de w caracteres blit (0-9a-f).
return function(sys)
  local ui, net = sys.ui, sys.net
  local gfx = ui.gfx

  local function parse(data)
    local lines = {}
    for line in (data .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local fps, w, h, nf = (lines[1] or ""):match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
    fps, w, h, nf = tonumber(fps), tonumber(w), tonumber(h), tonumber(nf)
    if not (fps and w and h and nf) then return nil end
    local frames, idx = {}, 2
    for f = 1, nf do
      local fr = {}
      for r = 1, h do fr[r] = lines[idx] or (("f"):rep(w)); idx = idx + 1 end
      frames[f] = fr
    end
    return { fps = fps, w = w, h = h, frames = frames }
  end

  local function play(name, label)
    ui.clear(); ui.bar("YouCube", true); ui.center(4, "Chargement...", colors.white)
    local rep = net.request({ action = "video", name = name }, 15)
    if not (rep and rep.ok and rep.data) then
      ui.message("YouCube", { "Echec : " .. tostring(rep and rep.error or "pas de reponse") }); return
    end
    local vid = parse(rep.data)
    if not vid then ui.message("YouCube", { "Format video invalide." }); return end

    local W = ui.size()
    local px0 = math.floor((W * 2 - vid.w) / 2) + 1
    local py0 = math.max(4, 4 + math.floor((51 - vid.h) / 2))
    local i, paused = 1, false
    local back, btns

    local function draw()
      gfx.begin(colors.black)
      back = ui.bar(label, true)
      gfx.text(2, 2, ("%d/%d"):format(i, #vid.frames), colors.lightGray, colors.black)
      gfx.right(W, 2, paused and "PAUSE" or "LECTURE",
        paused and colors.orange or colors.lime, colors.black)
      gfx.drawPixArt(px0, py0, vid.frames[i])
      btns = {}
      local function b(x, w, lab, col, id)
        gfx.roundRect(x, 20, w, 1, col, colors.black, 1)
        gfx.center(x + math.floor(w / 2), 20, lab, colors.white, col)
        btns[#btns + 1] = { x = x, y = 20, w = w, h = 1, id = id }
      end
      b(1, 10, paused and "Play" or "Pause", colors.green, "pause")
      b(12, 10, "Rejouer", colors.blue, "restart")
      b(23, 4, "<<", colors.gray, "list")
    end

    draw()
    local tick = os.startTimer(1 / vid.fps)
    while true do
      local ev = { os.pullEvent() }
      if ev[1] == "timer" and ev[2] == tick then
        if not paused then
          i = i + 1; if i > #vid.frames then i = 1 end
          draw()
        end
        tick = os.startTimer(1 / vid.fps)
      elseif ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
        if ui.hit(back, ev[3], ev[4]) then return end
        for _, bt in ipairs(btns) do
          if ui.hit(bt, ev[3], ev[4]) then
            if bt.id == "pause" then paused = not paused; draw()
            elseif bt.id == "restart" then i = 1; paused = false; draw()
            elseif bt.id == "list" then return end
            break
          end
        end
      elseif ev[1] == "key" then
        local k = ev[2]
        if k == keys.space then paused = not paused; draw()
        elseif k == keys.r then i = 1; draw()
        elseif k == keys.q or k == keys.backspace then return end
      end
    end
  end

  while true do
    ui.clear(); ui.bar("YouCube"); ui.center(4, "Chargement...", colors.lightGray)
    local reply = net.request({ action = "videolist" }, 6)
    if not reply then ui.message("YouCube", { "Serveur injoignable." }); return end
    local vids = reply.videos or {}
    if #vids == 0 then
      ui.message("YouCube", { "Aucune video sur le serveur.", "(ajoute des .nfv dans videos/)" }); return
    end
    local labels = {}
    for i, v in ipairs(vids) do labels[i] = v:gsub("%.nfv$", "") end
    local kind, idx = ui.list("YouCube - videos", labels)
    if kind == "back" then return end
    if kind == "item" then play(vids[idx], labels[idx]) end
  end
end
]=]
files["repo/Lecteur mp6.dis/package.info"] = [=[
{
  name = "Lecteur mp6",
  desc = "Lecteur video : joue en pixels les videos du dossier videos/ du serveur.",
  version = "1.0",
}
]=]
files["repo/pocketos/files/cobble/apps/bank.lua"] = [=[
-- @name Banque
-- Voir son solde, definir un code banque, envoyer de l'argent.
-- Toutes les donnees d'argent sont sur le SERVEUR (jamais sur le tel).
return function(sys)
  local ui, net = sys.ui, sys.net

  local function info()
    local r = net.auth({ action = "bank_info" }, 5)
    if r and r.ok then
      net.balance = r.balance or 0; net.hasBankPass = r.hasBankPass and true or false
      net.feeRate = r.feeRate or 0   -- taux de commission (preleve par le serveur)
    end
    return r
  end

  -- estimation de la commission (meme calcul que le serveur)
  local function feeOf(amount)
    local rate = net.feeRate or 0
    if rate <= 0 or amount <= 1 then return 0 end
    return math.min(amount - 1, math.ceil(amount * rate))
  end

  -- code banque saisi a l'ouverture, reutilise pour les transferts
  local bankpass = nil

  -- (1) charge le solde
  local r = info()
  if not r or not r.ok then
    ui.message("Banque", { "Serveur injoignable.", (r and r.error) or "" })
    return
  end

  -- (2) si un code banque existe, on le demande pour deverrouiller l'app
  if net.hasBankPass then
    local p = ui.input("Code banque", "", { mask = true })
    if not p then return end
    local v = net.auth({ action = "bank_verify", pass = p }, 5)
    if not (v and v.ok) then ui.message("Banque", { "Code incorrect." }); return end
    bankpass = p
  end

  local function setPass()
    local old = nil
    if net.hasBankPass then
      old = ui.input("Ancien code", "", { mask = true }); if not old then return end
    end
    local new = ui.input(net.hasBankPass and "Nouveau code" or "Choisir un code banque", "", { mask = true })
    if not new or new == "" then return end
    local new2 = ui.input("Confirmer le code", "", { mask = true })
    if new ~= new2 then ui.message("Banque", { "Codes differents." }); return end
    local resp = net.auth({ action = "bank_setpass", old = old, new = new }, 5)
    if resp and resp.ok then
      bankpass = new; net.hasBankPass = true
      ui.message("Banque", { "Code banque enregistre." })
    else
      ui.message("Banque", { (resp and resp.error) or "echec" })
    end
  end

  local function transfer()
    local to = ui.input("Destinataire (pseudo)")
    if not to or to == "" then return end
    local amtS = ui.input("Montant a envoyer")
    if not amtS then return end
    local amt = math.floor(tonumber(amtS) or 0)
    if amt <= 0 then ui.message("Banque", { "Montant invalide." }); return end
    -- si un code banque est defini mais pas encore saisi, le demander
    local bp = bankpass
    if net.hasBankPass and not bp then
      bp = ui.input("Code banque", "", { mask = true }); if not bp then return end
    end
    local est = feeOf(amt)
    local q = ("Envoyer %d a %s ?"):format(amt, to)
    if est > 0 then q = q .. (" Il recevra %d (commission %d)."):format(amt - est, est) end
    if not ui.confirm("Transfert", q) then return end
    local resp = net.auth({ action = "bank_transfer", to = to, amount = amt, bankpass = bp }, 6)
    if resp and resp.ok then
      net.balance = resp.balance or net.balance
      local lines = { ("Envoye : %d"):format(amt) }
      if (resp.fee or 0) > 0 then
        lines[#lines + 1] = ("Recu par %s : %d (comm. %d)"):format(to, resp.net or (amt - resp.fee), resp.fee)
      end
      lines[#lines + 1] = "Nouveau solde : " .. net.balance
      ui.message("Banque", lines)
    else
      ui.message("Banque", { (resp and resp.error) or "echec" })
    end
  end

  while true do
    info()
    local entries = {
      { label = net.balance .. " $",   sub = "solde du compte",   icon = "$", color = colors.green },
      { label = "Envoyer",             sub = "a un autre pseudo",  icon = ">", color = colors.orange },
      { label = net.hasBankPass and "Changer le code" or "Definir un code",
        sub = "code banque",           icon = "#", color = colors.blue },
    }
    local idx = ui.menu("Banque", entries, { status = "Compte : " .. ((net.session and net.session.user) or "?") })
    if idx == "back" then return end
    if idx == 1 then
      -- solde deja rafraichi par info() ; on l'affiche en grand
      ui.message("Solde", { net.balance .. " $", "sur le compte " .. ((net.session and net.session.user) or "") })
    elseif idx == 2 then transfer()
    elseif idx == 3 then setPass() end
  end
end
]=]
files["repo/pocketos/files/cobble/apps/chat.lua"] = [=[
-- @name Chat
-- Messagerie entre telephones. Historique stocke sur le SERVEUR (global).
return function(sys)
  local ui, net = sys.ui, sys.net
  local me = net.name or (net.session and net.session.user) or ""

  -- historique recupere depuis le serveur a l'ouverture
  local history = {}
  local r = net.request({ action = "chatlog" }, 5)
  if r and r.ok and type(r.history) == "table" then history = r.history end
  -- les messages recus en arriere-plan sont deja dans l'historique serveur
  net.inbox = {}

  local function isMe(m) return m.self or (m.from == me) end

  local back, wbtn

  local function draw()
    local W, H = ui.size()
    ui.clear()
    back = ui.bar("Chat", true)
    local rows = H - 2
    local start = math.max(1, #history - rows + 1)
    local y = 2
    for i = start, #history do
      local m = history[i]
      local mine = isMe(m)
      local who = mine and "moi" or (m.from or "?")
      ui.text(1, y, who .. ": ", mine and colors.lime or colors.cyan, colors.black)
      local mx = #who + 3
      ui.text(mx, y, tostring(m.text or ""):sub(1, W - mx + 1), colors.white, colors.black)
      y = y + 1
      if y > H - 1 then break end
    end
    if #history == 0 then
      ui.text(2, 3, "Aucun message.", colors.lightGray, colors.black)
    end
    wbtn = { x = 1, y = H, w = 9, h = 1 }
    ui.gfx.roundRect(1, H, 9, 1, colors.green, colors.black)
    ui.text(1, H, " Ecrire ", colors.white, colors.green)
  end

  local function write()
    local txt = ui.input("Message (a tous)")
    if txt and #txt > 0 then
      net.send({ action = "msg", text = txt })   -- le serveur persiste + relaie
      history[#history + 1] = { self = true, from = me, text = txt }
    end
  end

  draw()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      if ui.hit(back, ev[3], ev[4]) then return end
      if ui.hit(wbtn, ev[3], ev[4]) then write(); draw() end
    elseif ev[1] == "key" then
      if ev[2] == keys.q or ev[2] == keys.backspace then return
      elseif ev[2] == keys.t or ev[2] == keys.enter then write(); draw() end
    elseif ev[1] == "cobble_msg" then
      history[#history + 1] = ev[2]
      net.inbox = {}
      draw()
    end
  end
end
]=]
files["repo/pocketos/files/cobble/apps/settings.lua"] = [=[
-- @name Reglages
return function(sys)
  local ui, net, cfg = sys.ui, sys.net, sys.cfg
  local PROTECTED = { ["store.lua"] = true, ["chat.lua"] = true,
                      ["settings.lua"] = true, ["bank.lua"] = true }

  local function deleteApp()
    local dir = "cobble/apps"
    local files, labels = {}, {}
    for _, f in ipairs(fs.list(dir)) do
      if f:match("%.lua$") and not PROTECTED[f] then
        files[#files + 1] = f
        local h = fs.open(fs.combine(dir, f), "r")
        local first = h.readLine() or ""
        h.close()
        labels[#labels + 1] = (first:match("@name%s+(.+)$")) or f
      end
    end
    if #files == 0 then
      ui.message("Supprimer une app", { "Aucune app supprimable.",
        "(les apps systeme sont protegees)" })
      return
    end
    local kind, i = ui.list("Supprimer une app", labels)
    if kind == "item" then
      if ui.confirm("Supprimer", "Supprimer definitivement " .. labels[i] .. " ?") then
        fs.delete(fs.combine(dir, files[i]))
        ui.message("Supprimer une app", { labels[i] .. " supprimee." })
      end
    end
  end

  while true do
    local who = (net.session and net.session.user) or cfg.name
    local online = net.server and ("En ligne #" .. tostring(net.server)) or "Hors-ligne"
    local entries = {
      { label = "Compte",           sub = who,                     icon = "@", color = colors.cyan },
      { label = "Nom d'affichage",  sub = cfg.name,                icon = "N", color = colors.blue },
      { label = "Serveur",          sub = online,                  icon = "S", color = colors.lime },
      { label = "Mettre a jour",    sub = "derniere version de l'OS", icon = "U", color = colors.orange },
      { label = "Supprimer une app", sub = "desinstaller",         icon = "X", color = colors.red },
      { label = "Reconnecter",      sub = "relancer le reseau",    icon = "R", color = colors.lightBlue },
      { label = "Se deconnecter",   sub = "changer de compte",     icon = "!", color = colors.magenta },
    }
    local idx = ui.menu("Reglages", entries)
    if idx == "back" then return end

    do
      if idx == 1 then
        ui.message("Compte", { "Connecte en tant que :", who,
          "uid " .. tostring(net.session and net.session.uid) })

      elseif idx == 2 then
        local n = ui.input("Nom d'affichage", cfg.name)
        if n and #n > 0 then
          cfg.name = n; net.name = n; sys.saveCfg()   -- pousse le profil sur le serveur
          ui.message("Reglages", { "Nom change en : " .. n })
        end

      elseif idx == 3 then
        local r = net.request({ action = "ping" }, 3)
        if r then
          ui.message("Serveur", { "Connecte a : " .. tostring(r.server or "?"),
                                  "id serveur : " .. tostring(net.server) })
        else
          ui.message("Serveur", { "Injoignable." })
        end

      elseif idx == 4 then
        if ui.confirm("MAJ", "Telecharger et installer la derniere version de l'OS ?") then
          ui.clear(); ui.bar("MAJ"); ui.center(3, "Telechargement...", colors.white)
          local rep = net.request({ action = "install", pkg = "pocketos" }, 10)
          if rep and rep.ok and rep.data and rep.data.files then
            net.applyFiles(rep.data.files)
            ui.message("MAJ", { "OS mis a jour. Redemarrage..." })
            os.reboot()
          else
            ui.message("MAJ", { "Echec de la mise a jour." })
          end
        end

      elseif idx == 5 then
        deleteApp()

      elseif idx == 6 then
        net.server = nil
        if net.open() then
          net.hb()
          ui.message("Reseau", { "Reconnecte (serveur #" .. tostring(net.server) .. ")" })
        else
          ui.message("Reseau", { "Serveur introuvable." })
        end

      elseif idx == 7 then
        if ui.confirm("Deconnexion", "Se deconnecter de ce compte ? Le tel redemarrera sur l'ecran de connexion.") then
          net.auth({ action = "logout" }, 4)
          net.clearSession()
          ui.message("Deconnexion", { "Deconnecte. Redemarrage..." })
          os.reboot()
        end
      end
    end
  end
end
]=]
files["repo/pocketos/files/cobble/apps/store.lua"] = [=[
-- @name Magasin
-- Parcourt les paquets du serveur et les installe (souris + clavier).
return function(sys)
  local ui, net = sys.ui, sys.net
  while true do
    ui.clear(); ui.bar("Magasin"); ui.center(3, "Chargement...", colors.lightGray)
    local reply, err = net.request({ action = "list" }, 5)
    if not reply then
      ui.message("Magasin", { "Serveur injoignable", tostring(err) }); return
    end
    local pkgs = reply.packages or {}
    if #pkgs == 0 then ui.message("Magasin", { "Aucun paquet disponible." }); return end

    local PALETTE = { colors.blue, colors.green, colors.orange, colors.magenta,
                      colors.cyan, colors.red, colors.purple, colors.lightBlue }
    local entries = {}
    for i, p in ipairs(pkgs) do
      entries[i] = {
        label = p.name,
        sub   = "v" .. tostring(p.version or "?") .. "  -  toucher pour voir",
        icon  = p.name:sub(1, 1):upper(),
        color = PALETTE[((i - 1) % #PALETTE) + 1],
      }
    end
    local idx = ui.menu("Magasin", entries, { status = #pkgs .. " paquet(s) disponible(s)" })
    if idx == "back" then return end

    do
      local p = pkgs[idx]
      local W, H = ui.size()
      ui.clear()
      local back = ui.bar(p.name, true)
      local y = 3
      for _, seg in ipairs(ui.wrap(p.desc or "(pas de description)", W - 2)) do
        ui.text(2, y, seg, colors.white, colors.black); y = y + 1
      end
      y = y + 1
      ui.text(2, y, "version : " .. tostring(p.version or "?"), colors.lightGray, colors.black)

      local inst = { x = 2, y = H, w = 12, h = 1 }
      local ret  = { x = W - 8, y = H, w = 8, h = 1 }
      ui.gfx.roundRect(inst.x, H, inst.w, 1, colors.green, colors.black); ui.text(inst.x, H, " Installer ", colors.white, colors.green)
      ui.gfx.roundRect(ret.x, H, ret.w, 1, colors.gray, colors.black);    ui.text(ret.x, H, " Retour ", colors.white, colors.gray)

      local go = false
      while true do
        local ev = { os.pullEvent() }
        if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
          if ui.hit(inst, ev[3], ev[4]) then go = true; break end
          if ui.hit(ret, ev[3], ev[4]) or ui.hit(back, ev[3], ev[4]) then break end
        elseif ev[1] == "key" then
          if ev[2] == keys.enter then go = true; break end
          if ev[2] == keys.q or ev[2] == keys.backspace then break end
        end
      end

      if go then
        ui.clear(); ui.bar("Installation"); ui.center(3, "Telechargement...", colors.white)
        local rep = net.request({ action = "install", pkg = p.name }, 10)
        if rep and rep.ok and rep.data and rep.data.files then
          local n = net.applyFiles(rep.data.files)
          ui.message("Installe", {
            p.name .. " installe (" .. n .. " fichiers).",
            (p.name == "pocketos") and "Redemarre pour appliquer l'OS." or "Dispo dans le menu.",
          })
        else
          ui.message("Erreur", { "Echec : " .. tostring(rep and rep.error or "pas de reponse") })
        end
      end
    end
  end
end
]=]
files["repo/pocketos/files/cobble/gfx.lua"] = [=[
-- CobblePhone : moteur graphique SOUS-PIXEL (compositeur)
-- Ecran pocket = 26x20 cellules -> toile de 52x60 pixels (2x3 par cellule).
-- On dessine dans un tampon pixel + un calque texte, puis on "presente"
-- l'ensemble via term.blit (caracteres de dessin 2x3). Le texte reste en
-- police systeme (plus lisible qu'une pixel-font).
local gfx = {}

local HEX = "0123456789abcdef"
local BLIT, COL2HEX = {}, {}
for i = 0, 15 do
  local ch = HEX:sub(i + 1, i + 1)
  BLIT[ch] = 2 ^ i
  COL2HEX[2 ^ i] = ch
end
gfx.BLIT = BLIT

-- Palette "flat design" (ecrans Advanced)
gfx.palette = {
  [colors.white]=0xf5f6fa,[colors.orange]=0xe67e22,[colors.magenta]=0xe84393,
  [colors.lightBlue]=0x54a0ff,[colors.yellow]=0xfeca57,[colors.lime]=0x4cd137,
  [colors.pink]=0xff9ff3,[colors.gray]=0x2f3640,[colors.lightGray]=0x8395a7,
  [colors.cyan]=0x00d2d3,[colors.purple]=0x9b59b6,[colors.blue]=0x3742fa,
  [colors.brown]=0x795548,[colors.green]=0x27ae60,[colors.red]=0xee5253,
  [colors.black]=0x1e272e,
}
function gfx.applyPalette(t)
  t = t or term
  if not t.setPaletteColour then return end
  for c, hex in pairs(gfx.palette) do pcall(t.setPaletteColour, c, hex) end
end

-- ---- etat interne ----
local W, H = term.getSize()
local PW, PH = W * 2, H * 3
local pix, txt = {}, {}
local suspended = false

local function alloc()
  W, H = term.getSize(); PW, PH = W * 2, H * 3
  pix = {}
  for y = 1, PH do local r = {}; for x = 1, PW do r[x] = colors.black end; pix[y] = r end
  txt = {}
end
alloc()

function gfx.suspend(on) suspended = on and true or false end

function gfx.begin(bg)
  local sw, sh = term.getSize()
  if sw ~= W or sh ~= H then alloc() end
  bg = bg or colors.black
  for y = 1, PH do local r = pix[y]; for x = 1, PW do r[x] = bg end end
  for y = 1, H do txt[y] = nil end
end

function gfx.setPix(x, y, c)
  if x >= 1 and x <= PW and y >= 1 and y <= PH then pix[y][x] = c end
end

-- Remplissage par CELLULES (API compatible : x,y,w,h en cellules)
function gfx.fill(cx, cy, w, h, color)
  for j = 0, h - 1 do
    local cyy = cy + j
    if cyy >= 1 and cyy <= H then
      local by = (cyy - 1) * 3
      if txt[cyy] then for i = 0, w - 1 do txt[cyy][cx + i] = nil end end
      for i = 0, w - 1 do
        local cxx = cx + i
        if cxx >= 1 and cxx <= W then
          local bx = (cxx - 1) * 2
          pix[by+1][bx+1]=color; pix[by+1][bx+2]=color
          pix[by+2][bx+1]=color; pix[by+2][bx+2]=color
          pix[by+3][bx+1]=color; pix[by+3][bx+2]=color
        end
      end
    end
  end
end

-- Rectangle a coins arrondis (cellules) ; bg = couleur derriere pour creuser
function gfx.roundRect(cx, cy, w, h, color, bg, r)
  gfx.fill(cx, cy, w, h, color)
  r = r or 3
  if not bg or r < 1 then return end
  local x0 = (cx - 1) * 2 + 1
  local y0 = (cy - 1) * 3 + 1
  local x1 = x0 + w * 2 - 1
  local y1 = y0 + h * 3 - 1
  for i = 0, r - 1 do
    for j = 0, r - 1 do
      if i + j < r - 1 then
        gfx.setPix(x0 + i, y0 + j, bg)
        gfx.setPix(x1 - i, y0 + j, bg)
        gfx.setPix(x0 + i, y1 - j, bg)
        gfx.setPix(x1 - i, y1 - j, bg)
      end
    end
  end
end

-- Rectangle en PIXELS
function gfx.pixRect(px, py, w, h, color)
  for j = 0, h - 1 do for i = 0, w - 1 do gfx.setPix(px + i, py + j, color) end end
end

-- Dessine une image PIXEL (matrice de caracteres blit ; ' ' = transparent)
function gfx.drawPixArt(px, py, art)
  for r = 1, #art do
    local row = art[r]
    for c = 1, #row do
      local col = BLIT[row:sub(c, c)]
      if col then gfx.setPix(px + c - 1, py + r - 1, col) end
    end
  end
end

-- ---- calque texte (coordonnees en CELLULES) ----
function gfx.text(cx, cy, str, fg, bg)
  str = tostring(str); fg = fg or colors.white
  if cy < 1 or cy > H then return end
  txt[cy] = txt[cy] or {}
  local by = (cy - 1) * 3
  for i = 1, #str do
    local x = cx + i - 1
    if x >= 1 and x <= W then
      local b = bg
      if not b then b = pix[by + 1][(x - 1) * 2 + 1] or colors.black end
      txt[cy][x] = { ch = str:sub(i, i), fg = fg, bg = b }
    end
  end
end

function gfx.center(cx, y, s, fg, bg) gfx.text(cx - math.floor(#tostring(s) / 2), y, s, fg, bg) end
function gfx.right(rx, y, s, fg, bg) s = tostring(s); gfx.text(rx - #s + 1, y, s, fg, bg) end

function gfx.hit(b, mx, my)
  return b ~= nil and mx >= b.x and mx < b.x + b.w and my >= b.y and my < b.y + b.h
end

function gfx.wrap(str, width)
  str = tostring(str); local out = {}
  while #str > width do out[#out + 1] = str:sub(1, width); str = str:sub(width + 1) end
  out[#out + 1] = str; return out
end

-- ---- reduction 6 sous-pixels -> 1 caractere 2 couleurs ----
local function count6(x, a, b, c, d, e, f)
  local n = 0
  if a == x then n = n + 1 end; if b == x then n = n + 1 end; if c == x then n = n + 1 end
  if d == x then n = n + 1 end; if e == x then n = n + 1 end; if f == x then n = n + 1 end
  return n
end

local function cellChar(a, b, c, d, e, f)
  if a == b and a == c and a == d and a == e and a == f then return " ", a, a end
  local bg, bn = a, count6(a, a, b, c, d, e, f)
  local t
  t = count6(b, a, b, c, d, e, f); if t > bn then bg, bn = b, t end
  t = count6(c, a, b, c, d, e, f); if t > bn then bg, bn = c, t end
  t = count6(d, a, b, c, d, e, f); if t > bn then bg, bn = d, t end
  t = count6(e, a, b, c, d, e, f); if t > bn then bg, bn = e, t end
  t = count6(f, a, b, c, d, e, f); if t > bn then bg, bn = f, t end
  local fg = (a ~= bg and a) or (b ~= bg and b) or (c ~= bg and c)
          or (d ~= bg and d) or (e ~= bg and e) or f
  local n = 0
  if a ~= bg then n = n + 1 end
  if b ~= bg then n = n + 2 end
  if c ~= bg then n = n + 4 end
  if d ~= bg then n = n + 8 end
  if e ~= bg then n = n + 16 end
  if f ~= bg then
    n = 31 - n
    return string.char(128 + n), bg, fg
  else
    return string.char(128 + n), fg, bg
  end
end

-- ---- rendu final ----
function gfx.present()
  if suspended then return end
  local rc, rf, rb = {}, {}, {}
  for cy = 1, H do
    local tline = txt[cy]
    local by = (cy - 1) * 3
    for cx = 1, W do
      local tcell = tline and tline[cx]
      local ch, fc, bc
      if tcell then
        ch, fc, bc = tcell.ch, tcell.fg, tcell.bg
      else
        local bx = (cx - 1) * 2
        ch, fc, bc = cellChar(pix[by+1][bx+1], pix[by+1][bx+2],
                              pix[by+2][bx+1], pix[by+2][bx+2],
                              pix[by+3][bx+1], pix[by+3][bx+2])
      end
      rc[cx] = ch
      rf[cx] = COL2HEX[fc] or "0"
      rb[cx] = COL2HEX[bc] or "f"
    end
    term.setCursorPos(1, cy)
    term.blit(table.concat(rc), table.concat(rf), table.concat(rb))
  end
end

-- Image .nfp (cellules) chargee dans le tampon en 2x3 pixels par cellule
function gfx.loadNFP(path)
  if fs.exists(path) and paintutils and paintutils.loadImage then
    local ok, img = pcall(paintutils.loadImage, path)
    if ok then return img end
  end
  return nil
end
function gfx.drawNFP(img, px, py)
  if not img then return end
  for r = 1, #img do
    local row = img[r]
    for c = 1, #row do
      local col = row[c]
      if col and col ~= 0 then
        gfx.pixRect(px + (c - 1) * 2, py + (r - 1) * 3, 2, 3, col)
      end
    end
  end
end

return gfx
]=]
files["repo/pocketos/files/cobble/login.lua"] = [=[
-- CobblePhone : ecran de CONNEXION / CREATION de compte.
-- Toutes les donnees vivent sur le serveur ; le tel ne garde qu'un jeton.
-- Renvoie la reponse serveur (compte connecte) ou "power" (extinction).
return function(sys)
  local ui, net = sys.ui, sys.net

  -- enregistre la session renvoyee par le serveur (login/signup/resume)
  local function keep(r, fallbackUser)
    net.session = { uid = r.uid, token = r.token,
                    user = (r.profile and r.profile.name) or fallbackUser }
    net.saveSession()
    net.balance = r.balance or 0
    net.hasBankPass = r.hasBankPass and true or false
  end

  local function ensureServer()
    if net.server then return true end
    if net.open() then return true end
    ui.message("Connexion", { "Serveur KIT introuvable.", "Verifie l'Ender Modem", "puis reessaie." })
    return false
  end

  local function doLogin()
    local user = ui.input("Pseudo")
    if not user or user == "" then return false end
    local pass = ui.input("Mot de passe", "", { mask = true })
    if not pass or pass == "" then return false end
    if not ensureServer() then return false end
    ui.clear(); ui.bar("Connexion"); ui.center(3, "Verification...", colors.white)
    local r, err = net.request({ action = "login", user = user, pass = pass }, 6)
    if r and r.ok then keep(r, user); return r end
    ui.message("Echec", { (r and r.error) or err or "erreur reseau" })
    return false
  end

  local function doSignup()
    local user = ui.input("Choisir un pseudo")
    if not user or user == "" then return false end
    local pass = ui.input("Choisir un mot de passe", "", { mask = true })
    if not pass or pass == "" then return false end
    local pass2 = ui.input("Confirmer le mot de passe", "", { mask = true })
    if pass ~= pass2 then ui.message("Creation", { "Les mots de passe", "ne correspondent pas." }); return false end
    if not ensureServer() then return false end
    ui.clear(); ui.bar("Creation"); ui.center(3, "Creation du compte...", colors.white)
    local r, err = net.request({ action = "signup", user = user, pass = pass }, 6)
    if r and r.ok then keep(r, user); return r end
    ui.message("Echec", { (r and r.error) or err or "erreur reseau" })
    return false
  end

  net.open()  -- localise le serveur (silencieux)
  while true do
    local srv = net.server and ("Serveur KIT #" .. tostring(net.server)) or "Serveur introuvable"
    local entries = {
      { label = "Se connecter",   sub = "compte existant", icon = ">", color = colors.blue },
      { label = "Creer un compte", sub = "nouveau compte",  icon = "+", color = colors.green },
      { label = "Eteindre",       sub = "arreter le telephone", icon = "O", color = colors.red },
    }
    -- pas de fleche retour : on ne peut pas sortir de l'ecran de compte
    local idx = ui.menu("PIL - Compte", entries, { back = false, status = srv })
    if idx == 1 then
      local r = doLogin(); if r then return r end
    elseif idx == 2 then
      local r = doSignup(); if r then return r end
    elseif idx == 3 then
      return "power"
    end
  end
end
]=]
files["repo/pocketos/files/cobble/main.lua"] = [=[
-- CobblePhone OS : boucle principale (interface graphique sous-pixel)
local ROOT = "cobble/"

-- retire l'ancienne app Fichiers (elle exposait le code) si presente
if fs.exists(ROOT .. "apps/files.lua") then pcall(fs.delete, ROOT .. "apps/files.lua") end

local ui  = dofile(ROOT .. "ui.lua")
local net = dofile(ROOT .. "net.lua")
local gfx = ui.gfx

-- si un MONITEUR est branche (ordinateur de bureau), on affiche l'interface
-- dessus. On choisit l'echelle qui donne au moins 26x20 cellules.
do
  local mon = peripheral.find("monitor")
  if mon then
    local chosen = 0.5
    for _, s in ipairs({ 2, 1.5, 1, 0.5 }) do
      mon.setTextScale(s)
      local w, h = mon.getSize()
      if w >= 26 and h >= 20 then chosen = s; break end
    end
    mon.setTextScale(chosen)
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1, 1)
    print("PIL OS affiche sur le moniteur.")
    term.redirect(mon)
  end
end

-- couleurs riches sur les ecrans Advanced (degrade sinon)
pcall(gfx.applyPalette)

-- --- rendu + verrouillage (os.pullEvent) ---
-- (1) presente la toile sous-pixel avant chaque attente d'evenement ;
-- (2) neutralise Ctrl+T (terminate) => aucun acces au shell / au code.
local unpack = table.unpack or unpack
do
  local raw = os.pullEventRaw
  os.pullEvent = function(filter)
    gfx.present()
    while true do
      local e = { raw(filter) }
      if e[1] ~= "terminate" then return unpack(e) end
    end
  end
end

-- ---- profil (stocke sur le SERVEUR, jamais en local) ----
-- Ancien fichier de config local : on le supprime (les donnees sont serveur).
if fs.exists(ROOT .. "config.tbl") then pcall(fs.delete, ROOT .. "config.tbl") end
local cfg = { name = "PIL" }
-- Sauvegarde du profil = envoi au serveur (compte authentifie).
local function saveCfg()
  if type(cfg.name) ~= "string" or cfg.name == "" then cfg.name = "PIL" end
  net.auth({ action = "setprofile", data = cfg }, 4)
end

local sys = { ui = ui, net = net, cfg = cfg, saveCfg = saveCfg, root = ROOT }

-- Applique le profil recu du serveur (login / resume) a l'etat local
local function applyProfile(r)
  if r.profile and type(r.profile) == "table" then cfg = r.profile end
  if type(cfg.name) ~= "string" or cfg.name == "" then
    cfg.name = (net.session and net.session.user) or "PIL"
  end
  net.name = cfg.name
  net.balance = r.balance or 0
  net.hasBankPass = r.hasBankPass and true or false
  sys.cfg = cfg
  -- Ecrit l'identifiant de compte sur le tel. Quand on insere le tel dans un
  -- lecteur de disque (ATM), il est monte sur /disk -> l'ATM lit /disk/secu/id.
  if net.session and net.session.uid then
    pcall(function()
      if not fs.exists("secu") then fs.makeDir("secu") end
      local h = fs.open("secu/id", "w")
      h.write(textutils.serialise({ uid = net.session.uid, user = net.session.user }))
      h.close()
    end)
  end
end

-- ---- splash + logo + connexion ----
local W, H = ui.size()
gfx.begin(colors.black)
-- carte-logo : carre arrondi bleu centre
local bw, bh = 12, 8
local bx = math.floor((W - bw) / 2) + 1
local by = 3
gfx.roundRect(bx, by, bw, bh, colors.blue, colors.black, 4)
-- grand "P" en pixels (logo PIL)
local CMARK = {
  "0000000 ",
  "00000000",
  "00    00",
  "00    00",
  "00000000",
  "0000000 ",
  "00      ",
  "00      ",
  "00      ",
  "00      ",
  "00      ",
}
local px0 = (bx - 1) * 2 + 1
local py0 = (by - 1) * 3 + 1
gfx.drawPixArt(px0 + math.floor((bw * 2 - #CMARK[1]) / 2),
               py0 + math.floor((bh * 3 - #CMARK) / 2), CMARK)
ui.center(by + bh + 1, "PIL", colors.white)
ui.center(by + bh + 2, "v1.0", colors.lightGray)
ui.center(H - 2, "connexion...", colors.lightBlue)
net.open()
sleep(0.6)

-- ---- porte d'authentification : reprise auto, sinon ecran de login ----
local function ensureLogin()
  while true do
    net.loadSession()
    if not net.session then
      -- pas de session : ecran creer/connexion
      local login = dofile(ROOT .. "login.lua")
      local r = login(sys)
      if r == "power" then return false end
      applyProfile(r); return true
    end
    -- session presente : tenter la reprise automatique
    local r = net.request({ action = "resume", uid = net.session.uid, token = net.session.token }, 5)
    if r and r.ok then
      applyProfile(r); return true
    elseif r and not r.ok then
      net.clearSession()   -- refus explicite (expire / pris ailleurs) -> ecran login
    else
      -- pas de reponse : serveur momentanement injoignable, on GARDE la session
      net.server = nil; net.open()
      ui.clear(); ui.bar("Connexion")
      ui.center(3, "Serveur KIT injoignable", colors.white)
      ui.center(5, "Nouvel essai...", colors.lightGray)
      sleep(2)
    end
  end
end

if not ensureLogin() then
  ui.clear(); ui.center(math.floor(H / 2), "Extinction...", colors.white)
  sleep(0.4); os.shutdown()
end

-- ---- decouverte des apps installees dans cobble/apps ----
local function discoverApps()
  local list = {}
  local dir = ROOT .. "apps"
  if fs.exists(dir) then
    for _, f in ipairs(fs.list(dir)) do
      if f:match("%.lua$") then
        local label = f:gsub("%.lua$", "")
        local h = fs.open(fs.combine(dir, f), "r")
        local first = h.readLine() or ""
        h.close()
        local nm = first:match("@name%s+(.+)$")
        if nm then label = nm end
        list[#list + 1] = { name = label, file = "apps/" .. f }
      end
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- ---- ecouteur reseau de fond (chat en direct + push serveur) ----
local function listener()
  while true do
    local _, msg = rednet.receive(net.proto)
    if type(msg) == "table" then
      if msg.action == "msg" then
        table.insert(net.inbox, msg)
        os.queueEvent("cobble_msg", msg)
      elseif msg.action == "bank_event" then
        if msg.balance then net.balance = msg.balance end
        os.queueEvent("cobble_bank", msg)
      elseif msg.action == "push" and msg.data and msg.data.files then
        net.applyFiles(msg.data.files)
        if msg.pkg == "pocketos" then
          -- notice non bloquante puis redemarrage automatique
          local W, H = term.getSize()
          ui.gfx.fill(1, 1, W, H, colors.blue)
          ui.center(math.floor(H / 2), "MAJ recue du serveur", colors.white, colors.blue)
          ui.center(math.floor(H / 2) + 1, "redemarrage...", colors.lightBlue, colors.blue)
          sleep(1)
          os.reboot()
        else
          os.queueEvent("cobble_push", msg.pkg)
        end
      end
    end
  end
end

-- ---- accueil ----
local function home()
  while true do
    local apps = discoverApps()
    local sel = ui.launcher(cfg.name, apps, function()
      local s = net.server and ("En ligne  #" .. net.server) or "Hors-ligne"
      if #net.inbox > 0 then s = s .. "   Chat(" .. #net.inbox .. ")" end
      return s
    end)
    if sel == "power" then
      return
    elseif type(sel) == "number" and apps[sel] then
      local ok, err = pcall(function()
        local fn = dofile(ROOT .. apps[sel].file)
        if type(fn) == "function" then fn(sys) end
      end)
      if not ok then ui.message("Erreur", { tostring(err) }) end
    end
  end
end

-- ---- heartbeat : garde la session vivante cote serveur ----
-- Si le serveur repond explicitement que la session n'est plus valide
-- (compte repris sur un autre tel apres expiration), on revient au login.
local function heartbeat()
  while true do
    if net.session then
      local r = net.request({ action = "hb", uid = net.session.uid, token = net.session.token }, 4)
      if r and r.ok == false then
        net.clearSession()   -- session invalidee cote serveur -> retour au login
        os.reboot()
      end
    end
    sleep(8)
  end
end

parallel.waitForAny(home, listener, heartbeat)

-- "Eteindre" : on coupe vraiment le telephone (pas de retour au shell)
ui.clear()
ui.center(math.floor(select(2, ui.size()) / 2), "Extinction...", colors.white)
sleep(0.4)
os.shutdown()
]=]
files["repo/pocketos/files/cobble/net.lua"] = [=[
-- CobblePhone : bibliotheque reseau (rednet / protocole cobblenet)
local PROTO = "cobblenet"

-- net.session = { uid=, token=, user= } : seule donnee stockee sur le tel.
-- Tout le reste (profil, argent, chat) vit sur le serveur.
local net = { server = nil, inbox = {}, name = nil, proto = PROTO,
              session = nil, balance = 0, hasBankPass = false }
local SESSFILE = "cobble/session.tbl"

-- Ouvre tous les modems et localise le serveur
function net.open()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      rednet.open(name)
    end
  end
  net.server = rednet.lookup(PROTO, "server")
  return net.server ~= nil
end

function net.ensure()
  if net.server then return true end
  return net.open()
end

-- Envoi sans attendre de reponse
function net.send(msg)
  if not net.ensure() then return false, "serveur introuvable" end
  rednet.send(net.server, msg, PROTO)
  return true
end

-- Envoi + attente d'une reponse de meme "action"
-- (l'ecouteur de fond gere les messages "msg"/"push" en parallele)
function net.request(msg, timeout)
  if not net.ensure() then return nil, "serveur introuvable" end
  rednet.send(net.server, msg, PROTO)
  local deadline = os.clock() + (timeout or 5)
  while true do
    local remaining = deadline - os.clock()
    if remaining <= 0 then return nil, "pas de reponse" end
    local id, reply = rednet.receive(PROTO, remaining)
    if id == nil then
      return nil, "pas de reponse"
    elseif id == net.server and type(reply) == "table" and reply.action == msg.action then
      return reply
    end
  end
end

-- ---- session (jeton stocke localement) ----
function net.loadSession()
  if fs.exists(SESSFILE) then
    local h = fs.open(SESSFILE, "r")
    local ok, t = pcall(textutils.unserialise, h.readAll())
    h.close()
    if ok and type(t) == "table" and t.uid and t.token then net.session = t end
  end
  return net.session
end
function net.saveSession()
  if not net.session then return end
  local h = fs.open(SESSFILE, "w")
  h.write(textutils.serialise(net.session))
  h.close()
end
function net.clearSession()
  net.session = nil
  if fs.exists(SESSFILE) then fs.delete(SESSFILE) end
end

-- Requete AUTHENTIFIEE : injecte uid + jeton de la session courante
function net.auth(msg, timeout)
  if net.session then msg.uid = net.session.uid; msg.token = net.session.token end
  return net.request(msg, timeout)
end

-- Heartbeat (fire-and-forget) : maintient la session vivante cote serveur
function net.hb()
  if net.session then
    net.send({ action = "hb", uid = net.session.uid, token = net.session.token })
  end
end

-- Ecrit un ensemble de fichiers { ["chemin"]=contenu } sur le disque
function net.applyFiles(files)
  local n = 0
  for path, content in pairs(files) do
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(path, "w"); h.write(content); h.close()
    n = n + 1
  end
  return n
end

return net
]=]
files["repo/pocketos/files/cobble/ui.lua"] = [=[
-- CobblePhone : interface graphique (tuiles arrondies, icones-images)
-- Souris (clic) + clavier. Le "hover" n'existe pas en CC : on met a la
-- place une surbrillance de la tuile selectionnee + une animation d'appui.
local gfx = dofile("cobble/gfx.lua")
local ui = { gfx = gfx }

-- Tuiles : largeur 11 avec une marge d'1 cellule a gauche ET a droite
-- (evite que le lisere de selection tombe sur le bord de l'ecran)
local TILE_W, TILE_H = 11, 7

ui.size    = term.getSize
ui.hit     = gfx.hit
ui.wrap    = gfx.wrap
ui.fill    = gfx.fill
ui.text    = gfx.text
ui.present = gfx.present

-- ui.clear reinitialise la toile sous-pixel (le rendu se fait a l'attente
-- d'evenement, via l'override os.pullEvent pose dans main.lua)
function ui.clear(bg)
  gfx.begin(bg or colors.black)
end

function ui.center(y, str, fg, bg)
  local W = term.getSize()
  gfx.text(math.max(1, math.floor((W - #tostring(str)) / 2) + 1), y, str, fg, bg)
end

-- Barre de titre (ligne 1) : fleche retour optionnelle + horloge
function ui.bar(title, back)
  local W = term.getSize()
  gfx.fill(1, 1, W, 1, colors.blue)
  local bb, tx = nil, 2
  if back then
    gfx.fill(1, 1, 3, 1, colors.cyan)
    gfx.text(1, 1, " < ", colors.white, colors.cyan)
    bb = { x = 1, y = 1, w = 3, h = 1 }
    tx = 5
  end
  gfx.text(tx, 1, tostring(title):sub(1, W - tx - 6), colors.white, colors.blue)
  gfx.right(W, 1, textutils.formatTime(os.time(), true), colors.white, colors.blue)
  return bb
end

-- ================= Icones HD des apps (12x9 pixels) =================
-- Chaque caractere = 1 PIXEL (blit hex) ; ' ' = transparent (montre l'accent)
local ICONS = {
  ["apps/store.lua"] = { col = colors.magenta, art = {
    "    0  0    ",
    "   0    0   ",
    "  00000000  ",
    "  00000000  ",
    "  00444400  ",
    "  00444400  ",
    "  00444400  ",
    "  00000000  ",
    "            " } },
  ["apps/chat.lua"] = { col = colors.green, art = {
    "  00000000  ",
    " 0000000000 ",
    " 0000000000 ",
    " 0088880000 ",
    " 0088888800 ",
    " 0000000000 ",
    "  00000000  ",
    "   00       ",
    "  0         " } },
  ["apps/settings.lua"] = { col = colors.gray, art = {
    "    4  4    ",
    " 4  4444  4 ",
    " 4444444444 ",
    "  44444444  ",
    "  444ff444  ",
    "  44ffff44  ",
    "  444ff444  ",
    " 4444444444 ",
    " 4  4444  4 " } },
  ["apps/bank.lua"] = { col = colors.green, art = {
    "            ",
    "    4444    ",
    "   444444   ",
    "  44444444  ",
    " 4444444444 ",
    " 44 44 44 4 ",
    " 44 44 44 4 ",
    " 4444444444 ",
    "            " } },
  ["apps/horloge.lua"] = { col = colors.cyan, art = {
    "    0000    ",
    "  00000000  ",
    " 0000000000 ",
    " 0000ff0000 ",
    " 00000f0000 ",
    " 000000f000 ",
    " 0000000000 ",
    "  00000000  ",
    "    0000    " } },
  ["apps/calculatrice.lua"] = { col = colors.lightBlue, art = {
    "  77777777  ",
    "  7dddddd7  ",
    "  7dddddd7  ",
    "  77777777  ",
    "  70707077  ",
    "  70707077  ",
    "  70707077  ",
    "  77777777  ",
    "            " } },
  ["apps/2048.lua"] = { col = colors.orange, art = {
    "            ",
    " 0000 0000  ",
    " 0000 0000  ",
    " 0000 0000  ",
    "            ",
    " 0000 0000  ",
    " 0000 0000  ",
    " 0000 0000  ",
    "            " } },
  ["apps/snake.lua"] = { col = colors.gray, art = {
    "            ",
    " ddddddd    ",
    "       d    ",
    "  dddddd    ",
    "  d     ee  ",
    "  ddddd ee  ",
    "        d   ",
    "  ddddddd   ",
    "            " } },
  ["apps/youcube.lua"] = { col = colors.red, art = {
    "            ",
    "   00       ",
    "   0000     ",
    "   000000   ",
    "   00000000 ",
    "   000000   ",
    "   0000     ",
    "   00       ",
    "            " } },
}

-- Renvoie couleur d'accent, art HD (matrice pixel) ou image nfp
function ui.iconFor(app)
  local d = ICONS[app.file]
  local col = d and d.col or colors.blue
  local base = app.file:match("([^/]+)%.lua$")
  if base then
    local img = gfx.loadNFP("cobble/icons/" .. base .. ".nfp")
    if img then return col, nil, img end
  end
  return col, d and d.art or nil, nil
end

function ui.tile(x, y, app, selected)
  local accent, art, img = ui.iconFor(app)
  gfx.roundRect(x, y, TILE_W, TILE_H, accent, colors.black, 3)
  -- zone pixel de la tuile
  local px0 = (x - 1) * 2 + 1
  local py0 = (y - 1) * 3 + 1
  if img then
    local iw = #(img[1] or {}) * 2
    gfx.drawNFP(img, px0 + math.floor((TILE_W * 2 - iw) / 2), py0 + 3)
  elseif art then
    local aw = #art[1]
    gfx.drawPixArt(px0 + math.floor((TILE_W * 2 - aw) / 2), py0 + 3, art)
  else
    gfx.center(x + math.floor(TILE_W / 2), y + 2, app.name:sub(1, 1):upper(), colors.white, accent)
  end
  local nm = app.name:sub(1, TILE_W - 2)
  gfx.center(x + math.floor(TILE_W / 2), y + TILE_H - 2, nm,
    selected and colors.yellow or colors.white, accent)
  if selected then
    -- liseré de selection (contour pixel jaune, symetrique = coins ronds)
    local x1 = px0 + TILE_W * 2 - 1
    local y1 = py0 + TILE_H * 3 - 1
    for xx = px0 + 2, x1 - 2 do
      gfx.setPix(xx, py0, colors.yellow); gfx.setPix(xx, y1, colors.yellow)
    end
    for yy = py0 + 2, y1 - 2 do
      gfx.setPix(px0, yy, colors.yellow); gfx.setPix(x1, yy, colors.yellow)
    end
  end
end

-- ================= Ecran d'accueil (grille de tuiles) =================
function ui.launcher(title, apps, statusFn)
  local xs, ys = { 2, 15 }, { 3, 11 }
  local perPage = #xs * #ys
  local sel = 1
  local slots, buttons = {}, {}

  local function draw(flashIdx)
    local W, H = term.getSize()
    gfx.fill(1, 1, W, H, colors.black)
    gfx.fill(1, 1, W, 1, colors.blue)
    gfx.text(2, 1, tostring(title):sub(1, W - 8), colors.white, colors.blue)
    gfx.right(W, 1, textutils.formatTime(os.time(), true), colors.white, colors.blue)
    if statusFn then gfx.text(2, 2, statusFn():sub(1, W - 1), colors.lightGray, colors.black) end

    local page = math.floor((sel - 1) / perPage)
    local startI = page * perPage
    slots = {}
    local k = 0
    for _, yy in ipairs(ys) do
      for _, xx in ipairs(xs) do
        k = k + 1
        local i = startI + k
        local a = apps[i]
        if a then
          ui.tile(xx, yy, a, (i == sel) or (flashIdx == i))
          slots[#slots + 1] = { x = xx, y = yy, w = TILE_W, h = TILE_H, idx = i }
        end
      end
    end

    buttons = {}
    local pl = " Eteindre "
    local pb = { x = W - #pl, y = H, w = #pl, h = 1, id = "power" }
    gfx.roundRect(pb.x, H, #pl, 1, colors.red, colors.black)
    gfx.text(pb.x, H, pl, colors.white, colors.red)
    buttons[#buttons + 1] = pb

    local pages = math.max(1, math.ceil(#apps / perPage))
    if pages > 1 then
      gfx.roundRect(1, H, 3, 1, colors.gray, colors.black); gfx.text(1, H, " < ", colors.white, colors.gray)
      buttons[#buttons + 1] = { x = 1, y = H, w = 3, h = 1, id = "prev" }
      gfx.roundRect(5, H, 3, 1, colors.gray, colors.black); gfx.text(5, H, " > ", colors.white, colors.gray)
      buttons[#buttons + 1] = { x = 5, y = H, w = 3, h = 1, id = "next" }
      gfx.text(9, H, ("%d/%d"):format(page + 1, pages), colors.lightGray, colors.black)
    end
  end

  draw()
  while true do
    local timer = os.startTimer(1)
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == timer then
      draw()
    elseif ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      local mx, my, acted = ev[3], ev[4], false
      for _, b in ipairs(buttons) do
        if gfx.hit(b, mx, my) then
          if b.id == "power" then return "power"
          elseif b.id == "prev" then sel = math.max(1, sel - perPage); draw()
          elseif b.id == "next" then sel = math.min(#apps, sel + perPage); draw() end
          acted = true; break
        end
      end
      if not acted then
        for _, s in ipairs(slots) do
          if gfx.hit(s, mx, my) then
            sel = s.idx; draw(s.idx); sleep(0.08)
            return s.idx
          end
        end
      end
    elseif ev[1] == "key" then
      local k = ev[2]
      if k == keys.right then sel = math.min(#apps, sel + 1); draw()
      elseif k == keys.left then sel = math.max(1, sel - 1); draw()
      elseif k == keys.down then sel = math.min(#apps, sel + #xs); draw()
      elseif k == keys.up then sel = math.max(1, sel - #xs); draw()
      elseif k == keys.enter then draw(sel); sleep(0.08); return sel
      elseif k == keys.q then return "power" end
    end
  end
end

-- ================= Liste cliquable =================
function ui.list(title, items, opts)
  opts = opts or {}
  local buttons = opts.buttons or {}
  local sel, top = 1, 1
  local rowsHit, btnHit, backbox = {}, {}, nil

  local function draw()
    local W, H = term.getSize()
    gfx.fill(1, 1, W, H, colors.black)
    backbox = ui.bar(title, true)
    local footH = (#buttons > 0) and 1 or 0
    local first = 3
    local rows = H - first + 1 - footH
    if sel < top then top = sel end
    if sel > top + rows - 1 then top = sel - rows + 1 end
    rowsHit = {}
    for i = 0, rows - 1 do
      local idx = top + i
      local it = items[idx]
      if not it then break end
      local y = first + i
      if idx == sel then
        gfx.roundRect(1, y, W - 1, 1, colors.blue, colors.black)
        gfx.text(2, y, tostring(it):sub(1, W - 3), colors.white, colors.blue)
      else
        gfx.text(2, y, tostring(it):sub(1, W - 3), colors.lightGray, colors.black)
      end
      rowsHit[#rowsHit + 1] = { x = 1, y = y, w = W, h = 1, idx = idx }
    end
    btnHit = {}
    if #buttons > 0 then
      local x = 1
      for _, b in ipairs(buttons) do
        local lab = " " .. b.label .. " "
        gfx.roundRect(x, H, #lab, 1, b.color or colors.gray, colors.black)
        gfx.text(x, H, lab, colors.white, b.color or colors.gray)
        btnHit[#btnHit + 1] = { x = x, y = H, w = #lab, h = 1, id = b.id }
        x = x + #lab + 1
      end
    end
  end

  draw()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      local mx, my = ev[3], ev[4]
      if gfx.hit(backbox, mx, my) then return "back" end
      for _, b in ipairs(btnHit) do if gfx.hit(b, mx, my) then return "button", b.id end end
      for _, r in ipairs(rowsHit) do
        if gfx.hit(r, mx, my) then sel = r.idx; return "item", r.idx end
      end
    elseif ev[1] == "mouse_scroll" then
      sel = math.min(#items, math.max(1, sel + ev[2])); draw()
    elseif ev[1] == "key" then
      local k = ev[2]
      if k == keys.up then sel = (sel > 1) and sel - 1 or #items; draw()
      elseif k == keys.down then sel = (sel < #items) and sel + 1 or 1; draw()
      elseif k == keys.enter then return "item", sel
      elseif k == keys.q or k == keys.backspace then return "back" end
    end
  end
end

-- ================= Menu GRAPHIQUE (cartes) =================
-- Liste de cartes arrondies avec pastille d'icone + titre + sous-titre,
-- dans le style de l'accueil. Souris + clavier. Defilement automatique.
--   entries[i] = { label=, sub=, icon="A", color=colors.blue }
-- Renvoie l'index selectionne, ou "back".
function ui.menu(title, entries, opts)
  opts = opts or {}
  local CARD_H = 2
  local sel, top = 1, 1
  local backbox, rowsHit = nil, {}

  local function draw(flash)
    local W, H = term.getSize()
    gfx.fill(1, 1, W, H, colors.black)
    backbox = ui.bar(title, opts.back ~= false)
    if opts.status then
      gfx.text(2, 2, tostring(opts.status):sub(1, W - 1), colors.lightGray, colors.black)
    end
    local first = opts.status and 4 or 3
    local avail = H - first + 1
    local rows = math.max(1, math.floor((avail + 0) / (CARD_H)))
    if sel < top then top = sel end
    if sel > top + rows - 1 then top = sel - rows + 1 end

    rowsHit = {}
    for i = 0, rows - 1 do
      local idx = top + i
      local e = entries[idx]
      if not e then break end
      local y = first + i * CARD_H
      local selc = (idx == sel) or (flash == idx)
      local accent = e.color or colors.blue
      local cardBg = selc and accent or colors.gray
      -- carte
      gfx.roundRect(2, y, W - 2, CARD_H, cardBg, colors.black, 2)
      -- pastille d'icone a gauche
      local chipBg = selc and colors.white or accent
      local glyphFg = selc and accent or colors.white
      gfx.roundRect(3, y, 4, CARD_H, chipBg, cardBg, 1)
      gfx.center(4, y + math.floor((CARD_H - 1) / 2), tostring(e.icon or "?"):sub(1, 1), glyphFg, chipBg)
      -- textes
      local tx = 8
      local maxw = W - tx
      gfx.text(tx, y, tostring(e.label or ""):sub(1, maxw), colors.white, cardBg)
      if e.sub and e.sub ~= "" then
        gfx.text(tx, y + 1, tostring(e.sub):sub(1, maxw),
          selc and colors.white or colors.lightGray, cardBg)
      end
      rowsHit[#rowsHit + 1] = { x = 2, y = y, w = W - 2, h = CARD_H, idx = idx }
    end
    -- indicateurs de defilement
    if top > 1 then gfx.right(W - 1, first, "^", colors.yellow, colors.black) end
    if top + rows - 1 < #entries then gfx.right(W - 1, H, "v", colors.yellow, colors.black) end
    return rows
  end

  local rows = draw()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      local mx, my = ev[3], ev[4]
      if gfx.hit(backbox, mx, my) then return "back" end
      for _, r in ipairs(rowsHit) do
        if gfx.hit(r, mx, my) then sel = r.idx; draw(r.idx); sleep(0.08); return r.idx end
      end
    elseif ev[1] == "mouse_scroll" then
      sel = math.min(#entries, math.max(1, sel + ev[2])); rows = draw()
    elseif ev[1] == "key" then
      local k = ev[2]
      if k == keys.up then sel = (sel > 1) and sel - 1 or #entries; rows = draw()
      elseif k == keys.down then sel = (sel < #entries) and sel + 1 or 1; rows = draw()
      elseif k == keys.enter then draw(sel); sleep(0.08); return sel
      elseif k == keys.q or k == keys.backspace then return "back" end
    end
  end
end

-- ================= Dialogues =================
function ui.message(title, lines)
  local W, H = term.getSize()
  gfx.fill(1, 1, W, H, colors.black)
  ui.bar(title)
  if type(lines) ~= "table" then lines = { lines } end
  local y = 3
  for _, l in ipairs(lines) do
    for _, seg in ipairs(gfx.wrap(l, W - 2)) do
      if y <= H - 2 then gfx.text(2, y, seg, colors.white, colors.black); y = y + 1 end
    end
  end
  local lab = "   OK   "
  local bx = math.floor((W - #lab) / 2) + 1
  gfx.roundRect(bx, H, #lab, 1, colors.green, colors.black)
  gfx.text(bx, H, lab, colors.white, colors.green)
  local box = { x = bx, y = H, w = #lab, h = 1 }
  while true do
    local ev = { os.pullEvent() }
    if (ev[1] == "mouse_click" or ev[1] == "monitor_touch") and gfx.hit(box, ev[3], ev[4]) then return
    elseif ev[1] == "key" then return end
  end
end

function ui.confirm(title, question)
  local W, H = term.getSize()
  gfx.fill(1, 1, W, H, colors.black)
  ui.bar(title)
  local y = 3
  for _, seg in ipairs(gfx.wrap(question, W - 2)) do
    if y <= H - 2 then gfx.text(2, y, seg, colors.white, colors.black); y = y + 1 end
  end
  local yes = { x = 2, y = H, w = 6, h = 1 }
  local no  = { x = W - 5, y = H, w = 5, h = 1 }
  gfx.roundRect(yes.x, H, yes.w, 1, colors.green, colors.black); gfx.text(yes.x, H, " Oui ", colors.white, colors.green)
  gfx.roundRect(no.x, H, no.w, 1, colors.red, colors.black);    gfx.text(no.x, H, " Non", colors.white, colors.red)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      if gfx.hit(yes, ev[3], ev[4]) then return true end
      if gfx.hit(no, ev[3], ev[4]) then return false end
    elseif ev[1] == "key" then
      if ev[2] == keys.o or ev[2] == keys.y or ev[2] == keys.enter then return true end
      if ev[2] == keys.n or ev[2] == keys.q or ev[2] == keys.backspace then return false end
    end
  end
end

-- Saisie de texte SANS clavier virtuel : on tape au CLAVIER PHYSIQUE.
-- (Un ecran/moniteur sans clavier ne peut donc pas saisir de texte.)
-- Masque en points si opts.mask. Renvoie le texte (OK / Entree) ou nil (retour).
function ui.input(label, preset, opts)
  opts = opts or {}
  local text = preset or ""
  local backbox, okbox, clrbox

  local function draw()
    local W, H = term.getSize()
    gfx.begin(colors.black)
    backbox = ui.bar(label, true)
    -- champ de saisie (grand, arrondi)
    local fy = 4
    gfx.roundRect(2, fy, W - 2, 3, colors.gray, colors.black, 2)
    local shown = opts.mask and ("*"):rep(#text) or text
    local maxc = W - 4
    if #shown > maxc then shown = shown:sub(#shown - maxc + 1) end
    gfx.text(3, fy + 1, shown .. "_", colors.white, colors.gray)
    -- indication
    gfx.center(math.floor(W / 2), fy + 4, "Tape au clavier - Entree = OK", colors.lightGray, colors.black)
    -- boutons bas
    local okl = " OK "
    okbox = { x = W - #okl, y = H, w = #okl, h = 1 }
    gfx.roundRect(okbox.x, H, #okl, 1, colors.green, colors.black); gfx.text(okbox.x, H, okl, colors.white, colors.green)
    local clrl = " Effacer "
    clrbox = { x = 2, y = H, w = #clrl, h = 1 }
    gfx.roundRect(2, H, #clrl, 1, colors.gray, colors.black); gfx.text(2, H, clrl, colors.white, colors.gray)
  end

  draw()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "char" then
      text = text .. ev[2]; draw()
    elseif ev[1] == "paste" then
      text = text .. tostring(ev[2]); draw()
    elseif ev[1] == "key" then
      if ev[2] == keys.enter then return text
      elseif ev[2] == keys.backspace then text = text:sub(1, #text - 1); draw() end
    elseif ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      local mx, my = ev[3], ev[4]
      if ui.hit(backbox, mx, my) then return nil
      elseif ui.hit(okbox, mx, my) then return text
      elseif ui.hit(clrbox, mx, my) then text = ""; draw() end
    end
  end
end

-- Pave numerique TACTILE (style distributeur). Gros boutons 1-9,0,C,OK.
-- opts.mask -> masque en points ; opts.hint -> texte grise quand vide ;
-- opts.max -> longueur max (defaut 12). Renvoie la chaine (OK/Entree) ou nil.
function ui.keypad(label, opts)
  opts = opts or {}
  local text = ""
  local backbox, hit = nil, {}
  local KEYS = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" }, { "C", "0", "OK" } }

  local function draw()
    local W, H = term.getSize()
    gfx.begin(colors.black)
    backbox = ui.bar(label, true)
    -- champ d'affichage
    local fy = 3
    gfx.roundRect(2, fy, W - 2, 2, colors.gray, colors.black, 2)
    local shown, fg = text, colors.white
    if shown == "" then shown = opts.hint or ""; fg = colors.lightGray
    elseif opts.mask then shown = ("*"):rep(#text) end
    gfx.center(math.floor(W / 2), fy, shown, fg, colors.gray)
    -- pave
    hit = {}
    local topY = fy + 3
    local rows, cols = #KEYS, 3
    local kh = math.max(2, math.floor((H - topY + 1) / rows))
    local kw = math.max(3, math.floor((W - 2) / cols))
    local xoff = math.floor((W - kw * cols) / 2) + 1
    for r, row in ipairs(KEYS) do
      local y = topY + (r - 1) * kh
      for c, ch in ipairs(row) do
        local x = xoff + (c - 1) * kw
        local col = (ch == "OK") and colors.green or (ch == "C") and colors.red or colors.lightGray
        local kfg = (ch == "OK" or ch == "C") and colors.white or colors.black
        gfx.roundRect(x, y, kw - 1, kh - 1, col, colors.black, 2)
        gfx.center(x + math.floor((kw - 1) / 2), y + math.floor((kh - 1) / 2), ch, kfg, col)
        hit[#hit + 1] = { x = x, y = y, w = kw - 1, h = kh - 1, ch = ch }
      end
    end
  end

  draw()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      local mx, my = ev[3], ev[4]
      if ui.hit(backbox, mx, my) then return nil end
      for _, k in ipairs(hit) do
        if ui.hit(k, mx, my) then
          if k.ch == "OK" then return text
          elseif k.ch == "C" then text = text:sub(1, #text - 1)
          elseif #text < (opts.max or 12) then text = text .. k.ch end
          draw(); break
        end
      end
    elseif ev[1] == "char" then
      if ev[2]:match("%d") and #text < (opts.max or 12) then text = text .. ev[2]; draw() end
    elseif ev[1] == "key" then
      if ev[2] == keys.enter then return text
      elseif ev[2] == keys.backspace then text = text:sub(1, #text - 1); draw() end
    end
  end
end

function ui.hold()
  while true do
    local e = os.pullEvent()
    if e == "key" or e == "mouse_click" or e == "monitor_touch" then return end
  end
end

return ui
]=]
files["repo/pocketos/files/startup.lua"] = [=[
-- CobblePhone OS - lanceur verrouille (mode kiosque)
-- L'OS se lance seul au demarrage. L'utilisateur n'a PAS acces au shell
-- ni au code : Ctrl+T est neutralise et toute sortie relance l'OS.

local function launch()
  if fs.exists("cobble/main.lua") then
    shell.run("cobble/main.lua")
  else
    printError("OS introuvable : cobble/main.lua manquant.")
    sleep(2)
  end
end

while true do
  pcall(launch)   -- avale erreurs / terminate / sortie -> on relance l'OS
  sleep(0.2)
end
]=]
files["repo/pocketos/package.info"] = [=[
{
  name = "pocketos",
  desc = "PIL OS : comptes serveur, banque + ATM (carte /secu/id), chat, UI cartes/pave tactile.",
  version = "2.3",
}
]=]
files["repo/snake/files/cobble/apps/snake.lua"] = [=[
-- @name Snake
-- Snake temps reel. Fleches OU boutons tactiles. Meilleur score persistant.
return function(sys)
  local ui = sys.ui
  local gfx = ui.gfx
  math.randomseed((os.epoch and os.epoch("utc")) or os.time())

  -- terrain de jeu (cellules) : cols 1..26, lignes 3..14
  local XMIN, XMAX, YMIN, YMAX = 1, 26, 3, 14

  local BEST = "cobble/snake.best"
  local function loadBest()
    if fs.exists(BEST) then
      local h = fs.open(BEST, "r"); local n = tonumber(h.readAll()); h.close()
      return n or 0
    end
    return 0
  end
  local function saveBest(n) local h = fs.open(BEST, "w"); h.write(tostring(n)); h.close() end

  local snake, dir, nextDir, food, score, dead
  local best = loadBest()

  local function spawnFood()
    local occ = {}
    for _, s in ipairs(snake) do occ[s[1] .. "," .. s[2]] = true end
    local free = {}
    for x = XMIN, XMAX do
      for y = YMIN, YMAX do
        if not occ[x .. "," .. y] then free[#free + 1] = { x, y } end
      end
    end
    food = free[math.random(#free)]
  end

  local function reset()
    snake = { { 14, 8 }, { 13, 8 }, { 12, 8 } }
    dir, nextDir = { 1, 0 }, { 1, 0 }
    score, dead = 0, false
    spawnFood()
  end

  local function setDir(dx, dy)
    if dx == -dir[1] and dy == -dir[2] then return end  -- pas de demi-tour
    nextDir = { dx, dy }
  end

  local function step()
    if dead then return end
    dir = nextDir
    local hx, hy = snake[1][1] + dir[1], snake[1][2] + dir[2]
    if hx < XMIN or hx > XMAX or hy < YMIN or hy > YMAX then dead = true; return end
    for _, s in ipairs(snake) do if s[1] == hx and s[2] == hy then dead = true; return end end
    table.insert(snake, 1, { hx, hy })
    if food and hx == food[1] and hy == food[2] then
      score = score + 1
      if score > best then best = score; saveBest(best) end
      spawnFood()
    else
      table.remove(snake)
    end
  end

  local back, btns
  local function drawBtn(x, y, w, h, lab, col, id)
    gfx.roundRect(x, y, w, h, col, colors.black, 2)
    gfx.center(x + math.floor(w / 2), y + math.floor((h - 1) / 2), lab, colors.white, col)
    btns[#btns + 1] = { x = x, y = y, w = w, h = h, id = id }
  end

  local function draw()
    local W = ui.size()
    ui.clear()
    back = ui.bar("Snake", true)
    gfx.text(2, 2, "Score:" .. score, colors.white, colors.black)
    gfx.right(W, 2, "Best:" .. best, colors.lightGray, colors.black)
    gfx.fill(XMIN, YMIN, XMAX - XMIN + 1, YMAX - YMIN + 1, colors.gray)
    if food then gfx.fill(food[1], food[2], 1, 1, colors.red) end
    for i, s in ipairs(snake) do
      gfx.fill(s[1], s[2], 1, 1, (i == 1) and colors.lime or colors.green)
    end
    btns = {}
    drawBtn(10, 15, 7, 2, "^", colors.blue, "up")
    drawBtn(1, 17, 7, 2, "<", colors.blue, "left")
    drawBtn(10, 17, 7, 2, "v", colors.blue, "down")
    drawBtn(19, 17, 7, 2, ">", colors.blue, "right")
    drawBtn(1, 19, 16, 2, "Rejouer", colors.green, "new")
  end

  local SPEED = 0.18
  reset()
  draw()
  local tick = os.startTimer(SPEED)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == tick then
      step()
      draw()
      if dead then
        ui.message("Snake", { "Perdu ! Score: " .. score, "Meilleur: " .. best })
        reset(); draw()
      end
      tick = os.startTimer(SPEED)
    elseif ev[1] == "key" then
      local k = ev[2]
      if k == keys.up then setDir(0, -1)
      elseif k == keys.down then setDir(0, 1)
      elseif k == keys.left then setDir(-1, 0)
      elseif k == keys.right then setDir(1, 0)
      elseif k == keys.q or k == keys.backspace then return end
    elseif ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
      if ui.hit(back, ev[3], ev[4]) then return end
      for _, b in ipairs(btns) do
        if ui.hit(b, ev[3], ev[4]) then
          if b.id == "new" then reset(); draw()
          elseif b.id == "up" then setDir(0, -1)
          elseif b.id == "down" then setDir(0, 1)
          elseif b.id == "left" then setDir(-1, 0)
          elseif b.id == "right" then setDir(1, 0) end
          break
        end
      end
    end
  end
end
]=]
files["repo/snake/package.info"] = [=[
{
  name = "snake",
  desc = "Le jeu du Snake : mange les pommes, evite les murs et ta queue. Fleches ou boutons.",
  version = "1.0",
}
]=]
files["server.lua"] = [=[
--[[ CobbleNet Server ==========================================
  Tourne sur le PC serveur (PC 7).
  - Heberge un depot de programmes dans le dossier "repo/".
  - Repond aux telephones : liste, installation, relais de chat.
  - Affiche un DASHBOARD TACTILE sur un moniteur (si present) avec des
    boutons Push. Sinon, tout se pilote au clavier (P = push, Q = quit).
  Protocole rednet : "cobblenet"  /  hostname : "server"
=============================================================== ]]--

local gfx   = dofile("gfx.lua")
local PROTO = "cobblenet"
local HOST  = "server"        -- identite rednet pour la recherche (compat)
local SERVER_NAME = "KIT"     -- nom affiche du serveur
local ADMIN_PASS  = "__ADMIN_PASS__"     -- mot de passe de la console admin (a changer)
local REPO  = "repo"

-- ============ Commission -> entreprise (API V-SMP) =============
-- Chaque transaction d'argent (transfert, depot ATM, retrait ATM) est
-- taxee de TAX_RATE : la commission est prelevee sur le montant et
-- envoyee a l'entreprise TAX_ENTERPRISE via l'API web V-SMP (la meme
-- que celle du ServeurCentral). Les credits admin ne sont PAS taxes.
local TAX_RATE       = 0.02       -- 2% par transaction (0 = desactive)
local TAX_ENTERPRISE = "PIL"      -- entreprise creditee cote V-SMP
local VSMP_API_URL   = "https://venatictundra22.com/wp-json/vsmp/v1"
local VSMP_API_KEY   = "__VSMP_API_KEY__"
local FEESFILE       = "fees.tbl" -- commissions en attente d'envoi

-- ============ Journal (defini tot pour les ecritures disque) ===
local logs = {}
local function log(txt)
  logs[#logs + 1] = ("[%s] %s"):format(textutils.formatTime(os.time(), true), txt)
  while #logs > 30 do table.remove(logs, 1) end
end

-- Ecriture disque SURE : ne crashe jamais le serveur si le disque est plein
-- (grosses videos > computer_space_limit) ou en lecture seule -> logge l'erreur.
local function writeFile(path, data)
  local h, err = fs.open(path, "w")
  if not h then
    log("ERREUR ecriture " .. path .. " : " .. tostring(err) .. " (disque plein ?)")
    return false
  end
  h.write(data); h.close()
  return true
end

-- ============ Comptes / sessions ===============================
-- Toutes les donnees utilisateur vivent ICI (le telephone ne stocke qu'un
-- jeton de session). Un compte = un uid unique ; il ne peut etre connecte
-- que sur UN SEUL telephone a la fois (voir tryLogin/active).
local ACCOUNTS = "accounts.tbl"          -- base des comptes (persistante)
local CHATFILE = "chat.tbl"              -- historique de chat global
local SESSION_TIMEOUT = 30               -- s sans heartbeat => session liberee

local accounts, nextUid = {}, 1001       -- accounts[pseudo_minuscule] = compte
local active = {}                        -- active[uid] = { phone=id, last=clock }
local chatHist = {}                      -- { { from=, text=, time= }, ... }

local function loadAccounts()
  if fs.exists(ACCOUNTS) then
    local h = fs.open(ACCOUNTS, "r"); local ok, t = pcall(textutils.unserialise, h.readAll()); h.close()
    if ok and type(t) == "table" then accounts = t.accounts or {}; nextUid = t.nextUid or 1001 end
  end
end
local function saveAccounts()
  return writeFile(ACCOUNTS, textutils.serialise({ accounts = accounts, nextUid = nextUid }))
end
local function loadChat()
  if fs.exists(CHATFILE) then
    local h = fs.open(CHATFILE, "r"); local ok, t = pcall(textutils.unserialise, h.readAll()); h.close()
    if ok and type(t) == "table" then chatHist = t end
  end
end
local function saveChat()
  while #chatHist > 100 do table.remove(chatHist, 1) end
  return writeFile(CHATFILE, textutils.serialise(chatHist))
end

-- Hash de mot de passe : leger (pas de crypto forte en CC), mais suffisant
-- pour un jeu -> le fichier accounts.tbl ne contient pas les mdp en clair.
-- Salt par compte (le pseudo/uid) => 2 comptes au meme mdp ont un hash different.
local function hashpw(pw, salt)
  local s = tostring(pw) .. "$" .. tostring(salt)
  local a, b = 5381, 52711
  for i = 1, #s do
    local c = s:byte(i)
    a = (a * 33 + c) % 16777213
    b = (b * 31 + c * 7 + 131) % 16777199
  end
  return string.format("%06x%06x", a, b)
end
local function newToken()
  return string.format("%x%04x%04x", os.epoch("utc"), math.random(0, 0xffff), math.random(0, 0xffff))
end

local function accByUser(u) return accounts[tostring(u or ""):lower()] end
local function accByUid(uid)
  for _, a in pairs(accounts) do if a.uid == uid then return a end end
end

-- libere les sessions dont le telephone ne donne plus de nouvelles
local function sweepSessions()
  local now = os.clock()
  for uid, s in pairs(active) do
    if now - s.last > SESSION_TIMEOUT then active[uid] = nil end
  end
end
local function touch(uid, phone) active[uid] = { phone = phone, last = os.clock() } end

-- Verifie qu'une requete est authentifiee (uid + jeton valides) et
-- rafraichit la session. Un seul jeton valide existe par compte a la fois.
local function authOK(uid, token, phone)
  local a = accByUid(uid)
  if not a or not token or a.token ~= token then return nil end
  touch(uid, phone)
  return a
end

-- Tente d'ouvrir une session : REFUSE si le compte est deja connecte sur un
-- AUTRE telephone (session encore fraiche). Rotation du jeton a chaque login.
local function tryLogin(a, phone)
  sweepSessions()
  local s = active[a.uid]
  if s and s.phone ~= phone and (os.clock() - s.last) <= SESSION_TIMEOUT then
    return false, "compte deja connecte sur un autre telephone"
  end
  a.token = newToken()
  touch(a.uid, phone)
  return true
end

-- ============ Commissions (file d'envoi vers l'API) ============
-- Envoi HTTP NON bloquant : la reponse arrive par http_success /
-- http_failure dans la boucle principale (une seule requete a la fois,
-- l'URL suffit donc a l'identifier). Si le site est injoignable, la file
-- persiste dans fees.tbl et on reessaie automatiquement.
local FEE_URL = VSMP_API_URL .. "/enterprise/deposit"
local feeQueue, feeTotal = {}, 0
local feeInFlight, feeRetryAt, feeHttpWarned = false, 0, false

local function loadFees()
  if fs.exists(FEESFILE) then
    local h = fs.open(FEESFILE, "r"); local ok, t = pcall(textutils.unserialise, h.readAll()); h.close()
    if ok and type(t) == "table" then feeQueue = t.queue or {}; feeTotal = t.total or 0 end
  end
end
local function saveFees()
  return writeFile(FEESFILE, textutils.serialise({ queue = feeQueue, total = feeTotal }))
end

-- montant de la commission (arrondi superieur ; laisse toujours >= 1)
local function feeOf(amount)
  if TAX_RATE <= 0 or amount <= 1 then return 0 end
  return math.min(amount - 1, math.ceil(amount * TAX_RATE))
end

local function nonce()
  return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end))
end

-- envoie la 1re commission de la file (si aucune requete deja en cours)
local function flushFees()
  if feeInFlight or #feeQueue == 0 or os.clock() < feeRetryAt then return end
  if not http then
    if not feeHttpWarned then log("Commissions : API http desactivee (config CC) !"); feeHttpWarned = true end
    return
  end
  local f = feeQueue[1]
  http.request({
    url = FEE_URL, method = "POST",
    headers = { ["X-API-Key"] = VSMP_API_KEY, ["X-Request-Nonce"] = nonce(),
                ["Content-Type"] = "application/json" },
    body = textutils.serializeJSON({ username = f.user, amount = f.amount,
                                     enterprise = TAX_ENTERPRISE }),
  })
  feeInFlight = true
end

-- Preleve la commission sur une transaction : la met en file d'envoi
-- vers TAX_ENTERPRISE. Renvoie le montant preleve.
local function takeFee(user, amount)
  local f = feeOf(amount)
  if f > 0 then
    feeTotal = feeTotal + f
    feeQueue[#feeQueue + 1] = { user = user, amount = f, time = os.epoch("utc") }
    saveFees()
    log(("Commission %d (%s) -> %s"):format(f, user, TAX_ENTERPRISE))
    flushFees()
  end
  return f
end

-- reponse de l'API pour la commission en cours (appele par la boucle principale)
local function onFeeResponse(okHttp, handle, err)
  feeInFlight = false
  if okHttp then
    local body = handle.readAll() or ""; handle.close()
    local okj, res = pcall(textutils.unserializeJSON, body)
    if okj and type(res) == "table" and res.error then
      -- refus applicatif (ex: pseudo inconnu cote site) : nouvel essai
      -- plus tard ; abandon apres 5 refus pour ne pas bloquer la file
      local f = table.remove(feeQueue, 1)
      f.fails = (f.fails or 0) + 1
      if f.fails >= 5 then
        log("Commission ABANDONNEE (" .. tostring(res.error) .. ") : " .. f.amount .. " de " .. f.user)
      else
        feeQueue[#feeQueue + 1] = f
        log("Commission refusee (" .. tostring(res.error) .. "), nouvel essai...")
        feeRetryAt = os.clock() + 60
      end
      saveFees()
    else
      table.remove(feeQueue, 1); saveFees()
    end
  else
    if handle then pcall(handle.close) end
    log("Commissions : site injoignable (" .. tostring(err) .. ")")
    feeRetryAt = os.clock() + 30
  end
  flushFees()
end

-- ============ Reseau ============================================
local function openModems()
  local found = false
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then rednet.open(name); found = true end
  end
  return found
end

-- ============ Depot ============================================
local function listFiles(dir, base, out)
  out = out or {}; base = base or dir
  for _, entry in ipairs(fs.list(dir)) do
    local full = fs.combine(dir, entry)
    if fs.isDir(full) then listFiles(full, base, out)
    else out[#out + 1] = full:sub(#base + 2) end
  end
  return out
end

local function readInfo(pkg)
  local path = fs.combine(REPO, pkg .. "/package.info")
  local info = { name = pkg, desc = "", version = "1.0" }
  if fs.exists(path) then
    local h = fs.open(path, "r"); local data = h.readAll(); h.close()
    local ok, tbl = pcall(textutils.unserialise, data)
    if ok and type(tbl) == "table" then for k, v in pairs(tbl) do info[k] = v end end
  end
  return info
end

local function listPackages()
  local pkgs = {}
  if not fs.exists(REPO) then return pkgs end
  for _, entry in ipairs(fs.list(REPO)) do
    -- un paquet dont le nom finit par ".dis" est DESACTIVE (masque du store)
    if fs.isDir(fs.combine(REPO, entry)) and not entry:match("%.dis$") then
      pkgs[#pkgs + 1] = readInfo(entry)
    end
  end
  return pkgs
end

local function buildPackage(pkg)
  if pkg:match("%.dis$") then return nil, "paquet desactive" end
  local filesDir = fs.combine(REPO, pkg .. "/files")
  if not fs.exists(filesDir) then return nil, "paquet introuvable" end
  local files = {}
  for _, rel in ipairs(listFiles(filesDir, filesDir)) do
    local h = fs.open(fs.combine(filesDir, rel), "r"); files[rel] = h.readAll(); h.close()
  end
  return { files = files, info = readInfo(pkg) }
end

-- ============ Clients / logs ===================================
local clients = {}
local function clientName(id) local c = clients[id]; return (c and c.name) or ("phone-" .. id) end

-- ============ Ecran de l'ORDINATEUR (petit terminal) ===========
local function drawTerminal()
  local prevbg = colors.black
  term.setBackgroundColor(colors.black); term.clear()
  local w, h = term.getSize()
  gfx.fill(1, 1, w, 1, colors.blue)
  gfx.text(2, 1, SERVER_NAME .. " - serveur", colors.white, colors.blue)
  gfx.right(w, 1, textutils.formatTime(os.time(), true), colors.white, colors.blue)
  local online = 0; for _ in pairs(clients) do online = online + 1 end
  gfx.text(2, 3, ("Paquets: %d   En ligne: %d"):format(#listPackages(), online), colors.lightGray, colors.black)
  local pend = #feeQueue > 0 and (" (" .. #feeQueue .. " a envoyer)") or ""
  gfx.text(2, 4, ("Comm. %s %d%%: %d$%s"):format(TAX_ENTERPRISE, math.floor(TAX_RATE * 100 + 0.5), feeTotal, pend), colors.yellow, colors.black)
  gfx.text(2, 5, "-- Journal --", colors.gray, colors.black)
  local rows = h - 6
  local start = math.max(1, #logs - rows + 1)
  local y = 6
  for i = start, #logs do gfx.text(1, y, logs[i]:sub(1, w), colors.white, colors.black); y = y + 1 end
  gfx.fill(1, h, w, 1, colors.gray)
  gfx.text(1, h, " P=push  C=crediter  Q=quitter ", colors.white, colors.gray)
end

-- ============ DASHBOARD MONITEUR ===============================
local monBtns = {}
local function drawMonitor(mon)
  local prev = term.redirect(mon)
  local W, H = term.getSize()
  gfx.fill(1, 1, W, H, colors.black)
  gfx.fill(1, 1, W, 1, colors.blue)
  gfx.text(2, 1, SERVER_NAME .. "  -  serveur", colors.white, colors.blue)
  gfx.right(W, 1, textutils.formatTime(os.time(), true), colors.white, colors.blue)

  local names, online = {}, 0
  for id, c in pairs(clients) do online = online + 1; names[#names + 1] = { id = id, name = c.name } end
  gfx.text(2, 3, ("Paquets : %d"):format(#listPackages()), colors.lightGray, colors.black)
  gfx.text(2, 4, ("Telephones en ligne : %d"):format(online), colors.lime, colors.black)
  local pend = #feeQueue > 0 and (" (" .. #feeQueue .. " a envoyer)") or ""
  gfx.text(2, 5, ("Commission %s : %d$%s"):format(TAX_ENTERPRISE, feeTotal, pend), colors.yellow, colors.black)

  monBtns = {}
  gfx.text(2, 6, "-- Telephones --", colors.gray, colors.black)
  local y = 7
  if online == 0 then
    gfx.text(2, y, "(aucun connecte)", colors.lightGray, colors.black); y = y + 1
  end
  for _, c in ipairs(names) do
    if y > H - 6 then break end
    gfx.roundRect(2, y, W - 3, 1, colors.gray, colors.black)
    gfx.text(3, y, (c.name .. " #" .. c.id):sub(1, W - 16), colors.white, colors.gray)
    local bl = " Push OS "
    local bx = W - 2 - #bl
    gfx.roundRect(bx, y, #bl, 1, colors.green, colors.black)
    gfx.text(bx, y, bl, colors.white, colors.green)
    monBtns[#monBtns + 1] = { x = bx, y = y, w = #bl, h = 1, action = "push", id = c.id }
    y = y + 1
  end

  gfx.text(2, y + 1, "-- Journal --", colors.gray, colors.black)
  local logTop = y + 2
  local maxRows = (H - 1) - logTop
  if maxRows > 0 then
    local start = math.max(1, #logs - maxRows + 1)
    local ry = logTop
    for i = start, #logs do gfx.text(2, ry, logs[i]:sub(1, W - 2), colors.white, colors.black); ry = ry + 1 end
  end

  local ab = H
  local b1 = " Push OS -> tous "
  gfx.roundRect(2, ab, #b1, 1, colors.green, colors.black); gfx.text(2, ab, b1, colors.white, colors.green)
  monBtns[#monBtns + 1] = { x = 2, y = ab, w = #b1, h = 1, action = "pushall" }
  local b2 = " Rafraichir "
  local x2 = 2 + #b1 + 1
  gfx.roundRect(x2, ab, #b2, 1, colors.blue, colors.black); gfx.text(x2, ab, b2, colors.white, colors.blue)
  monBtns[#monBtns + 1] = { x = x2, y = ab, w = #b2, h = 1, action = "refresh" }

  term.redirect(prev)
end

-- ============ Push serveur -> telephone(s) =====================
local function pushTo(id, pkgName)
  local pkg, err = buildPackage(pkgName)
  if not pkg then log("Push echoue : " .. tostring(err)); return false end
  rednet.send(id, { ok = true, action = "push", pkg = pkgName, data = pkg }, PROTO)
  log("Push '" .. pkgName .. "' -> " .. clientName(id))
  return true
end

local function pushAll(pkgName)
  local n = 0
  for id in pairs(clients) do if pushTo(id, pkgName) then n = n + 1 end end
  log("Push '" .. pkgName .. "' vers " .. n .. " telephone(s)")
end

-- Saisie sur la derniere ligne du terminal de l'ordinateur
local function prompt(label)
  local _, h = term.getSize()
  gfx.fill(1, h, select(1, term.getSize()), 1, colors.black)
  term.setCursorPos(1, h); term.setTextColor(colors.yellow); term.write(label)
  term.setTextColor(colors.white); term.setCursorBlink(true)
  local s = read(); term.setCursorBlink(false)
  return s
end

local function doPushCommand()
  local target = prompt("Push vers (id ou 'all', vide=annule) : ")
  if not target or target == "" then return end
  local pkgName = prompt("Paquet [pocketos] : ")
  if not pkgName or pkgName == "" then pkgName = "pocketos" end
  if target == "all" then pushAll(pkgName)
  else
    local id = tonumber(target)
    if id then pushTo(id, pkgName) else log("Cible invalide : " .. tostring(target)) end
  end
end

local function handleMonitorTouch(x, y)
  for _, b in ipairs(monBtns) do
    if gfx.hit(b, x, y) then
      if b.action == "push" then pushTo(b.id, "pocketos")
      elseif b.action == "pushall" then pushAll("pocketos")
      elseif b.action == "refresh" then log("Rafraichi") end
      return
    end
  end
end

-- ============ Traitement des requetes ==========================
local function handle(senderId, msg)
  if type(msg) ~= "table" or not msg.action then return end
  -- toutes les actions admin_* (sauf le telechargement admin_app) exigent le mot de passe
  if type(msg.action) == "string" and msg.action:match("^admin_")
      and msg.action ~= "admin_app" and msg.pass ~= ADMIN_PASS then
    rednet.send(senderId, { ok = false, action = msg.action, error = "mot de passe incorrect" }, PROTO)
    return
  end
  if msg.action == "ping" then
    rednet.send(senderId, { ok = true, action = "pong", server = SERVER_NAME }, PROTO)
  elseif msg.action == "list" then
    rednet.send(senderId, { ok = true, action = "list", packages = listPackages() }, PROTO)
    log("Liste -> " .. clientName(senderId))
  elseif msg.action == "install" then
    local pkg, err = buildPackage(msg.pkg or "")
    if pkg then
      rednet.send(senderId, { ok = true, action = "install", pkg = msg.pkg, data = pkg }, PROTO)
      log("Install '" .. tostring(msg.pkg) .. "' -> " .. clientName(senderId))
    else
      rednet.send(senderId, { ok = false, action = "install", error = err }, PROTO)
      log("Echec install '" .. tostring(msg.pkg) .. "'")
    end
  elseif msg.action == "register" then
    clients[senderId] = { name = msg.name or ("phone-" .. senderId), last = os.clock() }
    rednet.send(senderId, { ok = true, action = "register" }, PROTO)
    log("Connexion : " .. clientName(senderId))
  elseif msg.action == "who" then
    local list = {}
    for id, c in pairs(clients) do list[#list + 1] = { id = id, name = c.name } end
    rednet.send(senderId, { ok = true, action = "who", clients = list }, PROTO)
  elseif msg.action == "msg" then
    local packet = { ok = true, action = "msg", from = clientName(senderId), fromId = senderId,
                     text = msg.text or "", time = textutils.formatTime(os.time(), true) }
    -- historique de chat GLOBAL persistant cote serveur
    chatHist[#chatHist + 1] = { from = packet.from, text = packet.text, time = packet.time }
    saveChat()
    if msg.to then rednet.send(tonumber(msg.to), packet, PROTO)
    else for id in pairs(clients) do if id ~= senderId then rednet.send(id, packet, PROTO) end end end
    log(clientName(senderId) .. ": " .. (msg.text or ""))

  elseif msg.action == "chatlog" then
    rednet.send(senderId, { ok = true, action = "chatlog", history = chatHist }, PROTO)

  -- ===================== COMPTES / AUTH =====================
  elseif msg.action == "signup" then
    local u = tostring(msg.user or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local key = u:lower()
    if #u < 3 then
      rednet.send(senderId, { ok = false, action = "signup", error = "pseudo trop court (min 3)" }, PROTO)
    elseif not u:match("^[%w_%-]+$") then
      rednet.send(senderId, { ok = false, action = "signup", error = "pseudo : lettres/chiffres seulement" }, PROTO)
    elseif #tostring(msg.pass or "") < 3 then
      rednet.send(senderId, { ok = false, action = "signup", error = "mot de passe trop court (min 3)" }, PROTO)
    elseif accounts[key] then
      rednet.send(senderId, { ok = false, action = "signup", error = "pseudo deja pris" }, PROTO)
    else
      local a = { user = u, pass = hashpw(msg.pass, key), uid = nextUid, balance = 0,
                  bankPass = nil, data = { name = u }, token = newToken(), created = os.epoch("utc") }
      nextUid = nextUid + 1
      accounts[key] = a
      touch(a.uid, senderId)
      saveAccounts()
      clients[senderId] = { name = u, uid = a.uid, last = os.clock() }
      rednet.send(senderId, { ok = true, action = "signup", uid = a.uid, token = a.token,
                              profile = a.data, balance = a.balance, hasBankPass = false }, PROTO)
      log("Nouveau compte : " .. u .. " (uid " .. a.uid .. ")")
    end

  elseif msg.action == "login" then
    local a = accByUser(msg.user)
    if not a or a.pass ~= hashpw(msg.pass, tostring(msg.user or ""):lower()) then
      rednet.send(senderId, { ok = false, action = "login", error = "pseudo ou mot de passe incorrect" }, PROTO)
    else
      local ok, err = tryLogin(a, senderId)
      if not ok then
        rednet.send(senderId, { ok = false, action = "login", error = err }, PROTO)
        log("Login refuse (" .. a.user .. ") : " .. err)
      else
        saveAccounts()
        clients[senderId] = { name = (a.data and a.data.name) or a.user, uid = a.uid, last = os.clock() }
        rednet.send(senderId, { ok = true, action = "login", uid = a.uid, token = a.token,
                                profile = a.data, balance = a.balance, hasBankPass = a.bankPass ~= nil }, PROTO)
        log("Login : " .. a.user)
      end
    end

  elseif msg.action == "resume" then
    -- reprise auto au demarrage du telephone (jeton stocke localement)
    local a = accByUid(msg.uid)
    if not a or a.token == nil or a.token ~= msg.token then
      rednet.send(senderId, { ok = false, action = "resume", error = "session expiree" }, PROTO)
    else
      sweepSessions()
      local s = active[a.uid]
      if s and s.phone ~= senderId and (os.clock() - s.last) <= SESSION_TIMEOUT then
        rednet.send(senderId, { ok = false, action = "resume", error = "compte connecte ailleurs" }, PROTO)
      else
        touch(a.uid, senderId)
        clients[senderId] = { name = (a.data and a.data.name) or a.user, uid = a.uid, last = os.clock() }
        rednet.send(senderId, { ok = true, action = "resume", uid = a.uid, token = a.token,
                                profile = a.data, balance = a.balance, hasBankPass = a.bankPass ~= nil }, PROTO)
        log("Reprise session : " .. a.user)
      end
    end

  elseif msg.action == "logout" then
    local a = authOK(msg.uid, msg.token, senderId)
    if a then
      a.token = nil; active[a.uid] = nil; saveAccounts(); clients[senderId] = nil
      log("Logout : " .. a.user)
    end
    rednet.send(senderId, { ok = true, action = "logout" }, PROTO)

  elseif msg.action == "hb" then
    -- heartbeat : garde la session vivante + met a jour le dashboard
    local a = authOK(msg.uid, msg.token, senderId)
    if a then
      clients[senderId] = clients[senderId] or { name = (a.data and a.data.name) or a.user, uid = a.uid }
      clients[senderId].last = os.clock()
    end
    rednet.send(senderId, { ok = a ~= nil, action = "hb" }, PROTO)

  elseif msg.action == "getprofile" then
    local a = authOK(msg.uid, msg.token, senderId)
    if a then rednet.send(senderId, { ok = true, action = "getprofile", profile = a.data,
                                      balance = a.balance, hasBankPass = a.bankPass ~= nil }, PROTO)
    else rednet.send(senderId, { ok = false, action = "getprofile", error = "non authentifie" }, PROTO) end

  elseif msg.action == "setprofile" then
    local a = authOK(msg.uid, msg.token, senderId)
    if not a then
      rednet.send(senderId, { ok = false, action = "setprofile", error = "non authentifie" }, PROTO)
    else
      if type(msg.data) == "table" then a.data = msg.data
      elseif msg.key then a.data = a.data or {}; a.data[msg.key] = msg.val end
      saveAccounts()
      if clients[senderId] then clients[senderId].name = (a.data and a.data.name) or a.user end
      rednet.send(senderId, { ok = true, action = "setprofile" }, PROTO)
    end

  -- ===================== BANQUE =====================
  elseif msg.action == "bank_info" then
    local a = authOK(msg.uid, msg.token, senderId)
    if a then rednet.send(senderId, { ok = true, action = "bank_info", balance = a.balance,
                                      hasBankPass = a.bankPass ~= nil, user = a.user, feeRate = TAX_RATE }, PROTO)
    else rednet.send(senderId, { ok = false, action = "bank_info", error = "non authentifie" }, PROTO) end

  elseif msg.action == "bank_setpass" then
    local a = authOK(msg.uid, msg.token, senderId)
    if not a then
      rednet.send(senderId, { ok = false, action = "bank_setpass", error = "non authentifie" }, PROTO)
    elseif a.bankPass ~= nil and a.bankPass ~= hashpw(msg.old or "", "bank" .. a.uid) then
      rednet.send(senderId, { ok = false, action = "bank_setpass", error = "ancien code incorrect" }, PROTO)
    elseif #tostring(msg.new or "") < 3 then
      rednet.send(senderId, { ok = false, action = "bank_setpass", error = "code trop court (min 3)" }, PROTO)
    else
      a.bankPass = hashpw(msg.new, "bank" .. a.uid); saveAccounts()
      rednet.send(senderId, { ok = true, action = "bank_setpass" }, PROTO)
      log("Code banque change : " .. a.user)
    end

  elseif msg.action == "bank_verify" then
    local a = authOK(msg.uid, msg.token, senderId)
    local ok = a and a.bankPass ~= nil and a.bankPass == hashpw(msg.pass or "", "bank" .. a.uid)
    rednet.send(senderId, { ok = ok == true, action = "bank_verify" }, PROTO)

  elseif msg.action == "bank_transfer" then
    local a = authOK(msg.uid, msg.token, senderId)
    if not a then
      rednet.send(senderId, { ok = false, action = "bank_transfer", error = "non authentifie" }, PROTO)
    elseif a.bankPass ~= nil and a.bankPass ~= hashpw(msg.bankpass or "", "bank" .. a.uid) then
      rednet.send(senderId, { ok = false, action = "bank_transfer", error = "code banque incorrect" }, PROTO)
    else
      local amount = math.floor(tonumber(msg.amount) or 0)
      local dest = accByUser(msg.to)
      if amount <= 0 then
        rednet.send(senderId, { ok = false, action = "bank_transfer", error = "montant invalide" }, PROTO)
      elseif not dest then
        rednet.send(senderId, { ok = false, action = "bank_transfer", error = "destinataire introuvable" }, PROTO)
      elseif dest.uid == a.uid then
        rednet.send(senderId, { ok = false, action = "bank_transfer", error = "destinataire = vous-meme" }, PROTO)
      elseif a.balance < amount then
        rednet.send(senderId, { ok = false, action = "bank_transfer", error = "solde insuffisant" }, PROTO)
      else
        local f = takeFee(a.user, amount)
        a.balance = a.balance - amount; dest.balance = dest.balance + (amount - f); saveAccounts()
        log(("Transfert %d (comm. %d) : %s -> %s"):format(amount, f, a.user, dest.user))
        for pid, c in pairs(clients) do
          if c.uid == dest.uid then
            rednet.send(pid, { ok = true, action = "bank_event",
                               text = ("Recu %d de %s"):format(amount - f, a.user), balance = dest.balance }, PROTO)
          end
        end
        rednet.send(senderId, { ok = true, action = "bank_transfer", balance = a.balance,
                                fee = f, net = amount - f }, PROTO)
      end
    end

  -- ===================== ATM (distributeur) =====================
  -- L'ATM s'authentifie par UID (lu sur le tel insere) OU par pseudo
  -- (tape au clavier de la borne) + code banque pour le retrait.
  -- Modele "solde seul" : depot = +, retrait = - (sur le solde serveur).
  elseif msg.action == "atm_info" then
    local a = msg.uid and accByUid(msg.uid) or accByUser(msg.user)
    if not a then rednet.send(senderId, { ok = false, action = "atm_info", error = "compte introuvable" }, PROTO)
    else rednet.send(senderId, { ok = true, action = "atm_info", user = a.user, uid = a.uid,
                                 balance = a.balance, hasBankPass = a.bankPass ~= nil, feeRate = TAX_RATE }, PROTO) end

  elseif msg.action == "atm_deposit" then
    local a = msg.uid and accByUid(msg.uid) or accByUser(msg.user)
    local amount = math.floor(tonumber(msg.amount) or 0)
    if not a then rednet.send(senderId, { ok = false, action = "atm_deposit", error = "compte introuvable" }, PROTO)
    elseif amount <= 0 then rednet.send(senderId, { ok = false, action = "atm_deposit", error = "montant invalide" }, PROTO)
    else
      local f = takeFee(a.user, amount)
      a.balance = a.balance + (amount - f); saveAccounts()
      log(("ATM depot %d (comm. %d) -> %s (%d)"):format(amount, f, a.user, a.balance))
      for pid, c in pairs(clients) do if c.uid == a.uid then
        rednet.send(pid, { ok = true, action = "bank_event", text = "Depot ATM +" .. (amount - f), balance = a.balance }, PROTO) end end
      rednet.send(senderId, { ok = true, action = "atm_deposit", balance = a.balance, fee = f, net = amount - f }, PROTO)
    end

  elseif msg.action == "atm_withdraw" then
    local a = msg.uid and accByUid(msg.uid) or accByUser(msg.user)
    local amount = math.floor(tonumber(msg.amount) or 0)
    if not a then rednet.send(senderId, { ok = false, action = "atm_withdraw", error = "compte introuvable" }, PROTO)
    elseif a.bankPass == nil then rednet.send(senderId, { ok = false, action = "atm_withdraw", error = "aucun code banque : retrait impossible" }, PROTO)
    elseif a.bankPass ~= hashpw(msg.bankpass or "", "bank" .. a.uid) then rednet.send(senderId, { ok = false, action = "atm_withdraw", error = "code banque incorrect" }, PROTO)
    elseif amount <= 0 then rednet.send(senderId, { ok = false, action = "atm_withdraw", error = "montant invalide" }, PROTO)
    elseif a.balance < amount then rednet.send(senderId, { ok = false, action = "atm_withdraw", error = "solde insuffisant" }, PROTO)
    else
      local f = takeFee(a.user, amount)
      a.balance = a.balance - amount; saveAccounts()
      log(("ATM retrait %d (comm. %d) -> %s (%d)"):format(amount, f, a.user, a.balance))
      for pid, c in pairs(clients) do if c.uid == a.uid then
        rednet.send(pid, { ok = true, action = "bank_event", text = "Retrait ATM -" .. amount, balance = a.balance }, PROTO) end end
      rednet.send(senderId, { ok = true, action = "atm_withdraw", balance = a.balance, fee = f, net = amount - f }, PROTO)
    end

  elseif msg.action == "atm_app" then
    -- telechargement de l'OS ATM (dossier atm/) - non protege
    local files = {}
    if fs.exists("atm") then
      for _, rel in ipairs(listFiles("atm", "atm")) do
        local h = fs.open(fs.combine("atm", rel), "r"); files[rel] = h.readAll(); h.close()
      end
    end
    rednet.send(senderId, { ok = true, action = "atm_app", data = { files = files } }, PROTO)
    log("ATM OS -> " .. clientName(senderId))

  elseif msg.action == "videolist" then
    local vids = {}
    if fs.exists("videos") then
      for _, f in ipairs(fs.list("videos")) do
        if not fs.isDir("videos/" .. f) and f:match("%.nfv$") then vids[#vids + 1] = f end
      end
    end
    rednet.send(senderId, { ok = true, action = "videolist", videos = vids }, PROTO)

  elseif msg.action == "video" then
    local path = "videos/" .. (msg.name or "")
    if fs.exists(path) and not fs.isDir(path) then
      local h = fs.open(path, "r"); local data = h.readAll(); h.close()
      rednet.send(senderId, { ok = true, action = "video", name = msg.name, data = data }, PROTO)
      log("Video '" .. tostring(msg.name) .. "' -> " .. clientName(senderId))
    else
      rednet.send(senderId, { ok = false, action = "video", error = "introuvable" }, PROTO)
    end

  -- ===================== CONSOLE ADMIN =====================
  elseif msg.action == "admin_app" then
    -- telechargement de l'OS admin (dossier admin/) - non protege
    local files = {}
    if fs.exists("admin") then
      for _, rel in ipairs(listFiles("admin", "admin")) do
        local h = fs.open(fs.combine("admin", rel), "r"); files[rel] = h.readAll(); h.close()
      end
    end
    rednet.send(senderId, { ok = true, action = "admin_app", data = { files = files } }, PROTO)
    log("Admin OS -> " .. clientName(senderId))

  elseif msg.action == "admin_auth" then
    rednet.send(senderId, { ok = true, action = "admin_auth", server = SERVER_NAME }, PROTO)

  elseif msg.action == "admin_clients" then
    local list = {}
    for id, c in pairs(clients) do list[#list + 1] = { id = id, name = c.name } end
    rednet.send(senderId, { ok = true, action = "admin_clients", clients = list }, PROTO)

  elseif msg.action == "admin_push" then
    local pkgName = msg.pkg or "pocketos"
    local pkg = buildPackage(pkgName)
    local n = 0
    if pkg then
      if msg.target == "all" then
        for id in pairs(clients) do rednet.send(id, { ok = true, action = "push", pkg = pkgName, data = pkg }, PROTO); n = n + 1 end
      else
        local id = tonumber(msg.target)
        if id then rednet.send(id, { ok = true, action = "push", pkg = pkgName, data = pkg }, PROTO); n = 1 end
      end
      log("Admin push '" .. pkgName .. "' x" .. n)
    end
    rednet.send(senderId, { ok = pkg ~= nil, action = "admin_push", count = n }, PROTO)

  elseif msg.action == "admin_broadcast" then
    local packet = { ok = true, action = "msg", from = "[ADMIN]", fromId = 0,
                     text = msg.text or "", time = textutils.formatTime(os.time(), true) }
    local n = 0
    for id in pairs(clients) do rednet.send(id, packet, PROTO); n = n + 1 end
    log("Admin broadcast: " .. (msg.text or ""))
    rednet.send(senderId, { ok = true, action = "admin_broadcast", count = n }, PROTO)

  elseif msg.action == "admin_pkgs" then
    local list = {}
    if fs.exists(REPO) then
      for _, entry in ipairs(fs.list(REPO)) do
        if fs.isDir(fs.combine(REPO, entry)) then
          local info = readInfo(entry)
          list[#list + 1] = { folder = entry, name = info.name or entry,
                              version = info.version, disabled = entry:match("%.dis$") ~= nil }
        end
      end
    end
    rednet.send(senderId, { ok = true, action = "admin_pkgs", pkgs = list }, PROTO)

  elseif msg.action == "admin_pkg_toggle" then
    local f = msg.folder
    local ok, err = false, "introuvable"
    if f and fs.exists(fs.combine(REPO, f)) then
      if f:gsub("%.dis$", "") == "pocketos" then err = "pocketos protege"
      else
        local newname = f:match("%.dis$") and f:gsub("%.dis$", "") or (f .. ".dis")
        fs.move(fs.combine(REPO, f), fs.combine(REPO, newname))
        log("Admin toggle " .. f .. " -> " .. newname); ok = true
      end
    end
    rednet.send(senderId, { ok = ok, action = "admin_pkg_toggle", error = err }, PROTO)

  elseif msg.action == "admin_pkg_delete" then
    local f = msg.folder
    local ok, err = false, "introuvable"
    if f and fs.exists(fs.combine(REPO, f)) then
      if f:gsub("%.dis$", "") == "pocketos" then err = "pocketos protege"
      else fs.delete(fs.combine(REPO, f)); log("Admin delete pkg " .. f); ok = true end
    end
    rednet.send(senderId, { ok = ok, action = "admin_pkg_delete", error = err }, PROTO)

  elseif msg.action == "admin_videos" then
    local vids = {}
    if fs.exists("videos") then
      for _, f in ipairs(fs.list("videos")) do
        if not fs.isDir("videos/" .. f) and f:match("%.nfv$") then vids[#vids + 1] = f end
      end
    end
    rednet.send(senderId, { ok = true, action = "admin_videos", videos = vids }, PROTO)

  elseif msg.action == "admin_video_delete" then
    local ok = false
    local p = "videos/" .. (msg.name or "")
    if msg.name and fs.exists(p) and not fs.isDir(p) then
      fs.delete(p); log("Admin delete video " .. msg.name); ok = true
    end
    rednet.send(senderId, { ok = ok, action = "admin_video_delete" }, PROTO)

  elseif msg.action == "admin_log" then
    rednet.send(senderId, { ok = true, action = "admin_log", logs = logs }, PROTO)

  elseif msg.action == "admin_accounts" then
    local list = {}
    for _, a in pairs(accounts) do
      list[#list + 1] = { user = a.user, uid = a.uid, balance = a.balance, online = active[a.uid] ~= nil }
    end
    table.sort(list, function(x, y) return x.user:lower() < y.user:lower() end)
    rednet.send(senderId, { ok = true, action = "admin_accounts", accounts = list }, PROTO)

  elseif msg.action == "admin_credit" then
    local a = accByUser(msg.user)
    if not a then
      rednet.send(senderId, { ok = false, action = "admin_credit", error = "compte introuvable" }, PROTO)
    else
      local delta = math.floor(tonumber(msg.amount) or 0)
      a.balance = math.max(0, a.balance + delta); saveAccounts()
      log(("Admin credit %s : %+d -> %d"):format(a.user, delta, a.balance))
      for pid, c in pairs(clients) do
        if c.uid == a.uid then
          rednet.send(pid, { ok = true, action = "bank_event", text = "Solde ajuste par l'admin", balance = a.balance }, PROTO)
        end
      end
      rednet.send(senderId, { ok = true, action = "admin_credit", balance = a.balance, user = a.user }, PROTO)
    end
  end
end

-- ============ Boucle principale ================================
if not openModems() then
  printError("Aucun modem trouve ! Attache un Ender Modem au serveur.")
  return
end

pcall(gfx.applyPalette, term)
local mon = peripheral.find("monitor")
if mon then
  pcall(mon.setTextScale, 0.5)
  pcall(gfx.applyPalette, mon)
end

math.randomseed(os.epoch("utc") % 2147483647)
loadAccounts()
loadChat()
loadFees()

rednet.host(PROTO, HOST)
do local n = 0; for _ in pairs(accounts) do n = n + 1 end
   log("Serveur demarre (id " .. os.getComputerID() .. ", " .. n .. " compte(s))") end
if TAX_RATE > 0 then
  log(("Commission %d%% -> %s (%d en attente d'envoi)"):format(
    math.floor(TAX_RATE * 100 + 0.5), TAX_ENTERPRISE, #feeQueue))
  flushFees()
end

-- Credit/debit d'un compte depuis le terminal serveur (touche C)
local function doCreditCommand()
  local u = prompt("Crediter le compte (pseudo) : ")
  if not u or u == "" then return end
  local a = accByUser(u)
  if not a then log("Compte introuvable : " .. u); return end
  local amt = prompt(("Montant (+/-) pour %s [solde %d] : "):format(a.user, a.balance))
  local delta = math.floor(tonumber(amt) or 0)
  if delta == 0 then return end
  a.balance = math.max(0, a.balance + delta); saveAccounts()
  for pid, c in pairs(clients) do
    if c.uid == a.uid then
      rednet.send(pid, { ok = true, action = "bank_event", text = "Solde ajuste par l'admin", balance = a.balance }, PROTO)
    end
  end
  log(("Credit %s : %+d -> %d"):format(a.user, delta, a.balance))
end

local function redraw()
  drawTerminal()
  if mon then pcall(drawMonitor, mon) end
end
redraw()

while true do
  local timer = os.startTimer(1)
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == timer then
    sweepSessions()
    -- retire du dashboard les telephones qui ne donnent plus de heartbeat
    local now = os.clock()
    for id, c in pairs(clients) do
      if c.last and now - c.last > SESSION_TIMEOUT then clients[id] = nil end
    end
    flushFees()   -- reessaie l'envoi des commissions apres un echec
    redraw()
  elseif ev[1] == "http_success" and ev[2] == FEE_URL then
    onFeeResponse(true, ev[3]); redraw()
  elseif ev[1] == "http_failure" and ev[2] == FEE_URL then
    onFeeResponse(false, ev[4], ev[3]); redraw()
  elseif ev[1] == "rednet_message" and ev[4] == PROTO then
    handle(ev[2], ev[3]); redraw()
  elseif ev[1] == "monitor_touch" then
    handleMonitorTouch(ev[3], ev[4]); redraw()
  elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
    mon = peripheral.find("monitor")
    if mon then pcall(mon.setTextScale, 0.5); pcall(gfx.applyPalette, mon) end
    redraw()
  elseif ev[1] == "key" and ev[2] == keys.p then
    doPushCommand(); redraw()
  elseif ev[1] == "key" and ev[2] == keys.c then
    doCreditCommand(); redraw()
  elseif ev[1] == "key" and ev[2] == keys.q then
    rednet.unhost(PROTO)
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
    print("Serveur arrete.")
    return
  end
end
]=]
files["startup.lua"] = [=[
-- CobbleNet - demarrage du serveur (PC 7)
-- Lance le serveur automatiquement au boot.
if fs.exists("server.lua") then
  shell.run("server.lua")
else
  print("server.lua introuvable !")
end
]=]

-- ---- secrets : saisis au clavier, jamais stockes dans ce fichier ----
term.clear(); term.setCursorPos(1, 1)
print("== Installation du serveur KIT ==")
print("")
print("Mot de passe ADMIN de la console (vide = 'kit') :")
write("> ")
local adminPass = read("*")
if adminPass == "" then adminPass = "kit" end
print("Cle API V-SMP pour les commissions")
print("(vide = a completer plus tard dans server.lua) :")
write("> ")
local apiKey = read()
local keyLater = false
if apiKey == "" then apiKey = "METS_TA_CLE_API_ICI"; keyLater = true end
files["server.lua"] = files["server.lua"]
  :gsub("__ADMIN_PASS__", function() return adminPass end)
  :gsub("__VSMP_API_KEY__", function() return apiKey end)

-- ---- ecriture sur le disque ----
print("")
print("Installation...")
local names = {}
for path in pairs(files) do names[#names + 1] = path end
table.sort(names)
local n = 0
for _, path in ipairs(names) do
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h, err = fs.open(path, "w")
  if not h then error("Impossible d'ecrire " .. path .. " : " .. tostring(err), 0) end
  h.write(files[path]); h.close()
  n = n + 1
end
print(n .. " fichiers installes.")

-- ---- verifications ----
local hasModem = false
for _, nm in ipairs(peripheral.getNames()) do
  if peripheral.getType(nm) == "modem" then hasModem = true end
end
if not hasModem then
  print("")
  print("ATTENTION : aucun modem detecte !")
  print("Attache un ENDER MODEM a cet ordinateur,")
  print("le serveur en a besoin pour fonctionner.")
end
if keyLater then
  print("")
  print("RAPPEL : pas de cle API saisie. Les commissions")
  print("resteront en attente tant que VSMP_API_KEY n'est")
  print("pas remplie en haut de server.lua (edit server.lua).")
end
print("")
print("Redemarrage sur le serveur dans 3 s...")
sleep(3)
os.reboot()
