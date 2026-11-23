local _, ns = ...

local UI = {}
ns.UI = UI

UI.COLORS = {
    window = { 0.078, 0.076, 0.072, 0.98 },
    control = { 0.149, 0.145, 0.137, 1 },
    controlHover = { 0.196, 0.190, 0.180, 1 },
    selected = { 0.243, 0.235, 0.220, 1 },
    text = { 0.957, 0.949, 0.929, 1 },
    muted = { 0.808, 0.788, 0.749, 1 },
    faint = { 0.659, 0.639, 0.600, 1 },
    accent = { 0.902, 0.698, 0.282, 1 },
    accentHover = { 0.973, 0.792, 0.420, 1 },
    dangerHover = { 0.333, 0.180, 0.165, 1 },
    onAccent = { 0.098, 0.074, 0.031, 1 },
    good = { 0.443, 0.800, 0.494, 1 },
    warn = { 0.957, 0.722, 0.298, 1 },
    bad = { 0.941, 0.416, 0.380, 1 },
}

UI.TEXT = {
    title = 17,
    heading = 13,
    body = 13,
    label = 12,
    caption = 11,
}

local FONT_DIR = "Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Fonts\\"
local FACES = {
    regular = FONT_DIR .. "FiraSans-Regular.ttf",
    bold = FONT_DIR .. "FiraSans-Medium.ttf",
}

local OTHER_ALPHABETS = {
    { "korean", "Fonts\\2002.TTF" },
    { "simplifiedchinese", "Fonts\\ARKai_T.ttf" },
    { "traditionalchinese", "Fonts\\blei00d.TTF" },
}
local fonts = {}
local fontSerial = 0

local function BuildFamily(name, face, size, flags)
    if not CreateFontFamily then return nil end
    local members = {
        { alphabet = "roman", file = face, height = size, flags = flags },
        { alphabet = "russian", file = face, height = size, flags = flags },
    }
    for _, face in ipairs(OTHER_ALPHABETS) do
        members[#members + 1] = { alphabet = face[1], file = face[2], height = size, flags = flags }
    end
    local ok, family = pcall(CreateFontFamily, name, members)
    return ok and family or nil
end

local function BuildFont(weight, size, flags)
    fontSerial = fontSerial + 1
    local name = ns.ADDON .. "Font" .. fontSerial
    local face = FACES[weight]
    local font = BuildFamily(name, face, size, flags)
    if font then return font end
    font = CreateFont(name)
    font:SetFont(face, size, flags)
    return font
end

local function CachedFont(weight, size, flags)
    flags = flags or ""
    local id = weight .. size .. flags
    local font = fonts[id]
    if not font then
        font = BuildFont(weight, size, flags)
        font:SetShadowOffset(0, 0)
        fonts[id] = font
    end
    return font
end

function UI.Font(size, flags)
    return CachedFont("regular", size, flags)
end

function UI.BoldFont(size, flags)
    return CachedFont("bold", size, flags)
end

local function NewText(parent, font, color, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFontObject(font)
    text:SetTextColor(unpack(color or UI.COLORS.text))
    text:SetWordWrap(false)
    return text
end

function UI.Text(parent, size, color, flags, layer)
    return NewText(parent, UI.Font(size, flags), color, layer)
end

function UI.BoldText(parent, size, color)
    return NewText(parent, UI.BoldFont(size), color)
end

function UI.Fill(parent, color, layer, subLevel)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel)
    texture:SetColorTexture(unpack(color))
    texture:SetAllPoints()
    return texture
end

function UI.Lerp(a, b, t)
    return a + (b - a) * t
end

function UI.LerpColor(from, to, t, out)
    out[1] = from[1] + (to[1] - from[1]) * t
    out[2] = from[2] + (to[2] - from[2]) * t
    out[3] = from[3] + (to[3] - from[3]) * t
    out[4] = (from[4] or 1) + ((to[4] or 1) - (from[4] or 1)) * t
    return out
end

local function EaseOutCubic(t)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

local tweens = {}
local incoming = {}
local finished = {}
local stepping = false
local tweenDriver = CreateFrame("Frame")
tweenDriver:Hide()

local function Advance(owner, tween, elapsed)
    tween.elapsed = tween.elapsed + elapsed
    local t = tween.duration > 0 and math.min(1, tween.elapsed / tween.duration) or 1
    local value = UI.Lerp(tween.from, tween.to, EaseOutCubic(t))
    owner.tweenValue = value
    tween.apply(owner, value)
    return t >= 1
end

tweenDriver:SetScript("OnUpdate", function(self, elapsed)
    stepping = true
    for owner, tween in pairs(tweens) do
        if Advance(owner, tween, elapsed) then
            finished[#finished + 1] = owner
        end
    end
    stepping = false
    for i = #finished, 1, -1 do
        local owner = finished[i]
        local tween = tweens[owner]
        finished[i] = nil
        tweens[owner] = nil
        if tween and tween.done then tween.done(owner) end
    end
    for owner, tween in pairs(incoming) do
        tweens[owner] = tween
        incoming[owner] = nil
    end
    if not next(tweens) then
        self:Hide()
    end
end)

local function Pending(owner)
    return incoming[owner] or tweens[owner]
end

function UI.Tween(owner, to, duration, apply, done)
    local from = owner.tweenValue or to
    local tween = Pending(owner)
    if from == to and not tween then
        owner.tweenValue = to
        apply(owner, to)
        if done then done(owner) end
        return
    end
    tween = tween or {}
    tween.from = from
    tween.to = to
    tween.duration = duration
    tween.elapsed = 0
    tween.apply = apply
    tween.done = done
    if stepping then
        incoming[owner] = tween
    else
        tweens[owner] = tween
    end
    tweenDriver:Show()
end

function UI.StopTween(owner)
    tweens[owner] = nil
    incoming[owner] = nil
end

function UI.SnapTween(owner, value, apply)
    tweens[owner] = nil
    incoming[owner] = nil
    owner.tweenValue = value
    apply(owner, value)
end

function UI.ClassColor(class)
    local color = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
    if not color then return 0.8, 0.8, 0.8 end
    return color.r, color.g, color.b
end

function UI.ClassName(class)
    return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
end

UI.ADDON_ICON = "Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Icon"

local GLYPH_LEFT, GLYPH_RIGHT, GLYPH_TOP, GLYPH_BOTTOM = 6 / 64, 58 / 64, 6 / 64, 58 / 64
local GLYPH_ASPECT = (GLYPH_RIGHT - GLYPH_LEFT) / (GLYPH_BOTTOM - GLYPH_TOP)

function UI.VerticalAnchor(owner)
    local _, y = owner:GetCenter()
    if not y then return "ANCHOR_TOP" end
    local screen = UIParent:GetHeight() * UIParent:GetEffectiveScale()
    return y * owner:GetEffectiveScale() > screen / 2 and "ANCHOR_BOTTOM" or "ANCHOR_TOP"
end

function UI.AddonGlyph(parent, height, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetTexture(UI.ADDON_ICON)
    texture:SetTexCoord(GLYPH_LEFT, GLYPH_RIGHT, GLYPH_TOP, GLYPH_BOTTOM)
    texture:SetSize(height * GLYPH_ASPECT, height)
    return texture
end

local CLASS_ICON_FILE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

function UI.SetClassIcon(texture, class)
    local atlas = "classicon-" .. string.lower(class)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        return
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    texture:SetTexture(CLASS_ICON_FILE)
    if coords then
        texture:SetTexCoord(unpack(coords))
    end
end

function UI.FadeIn(frame, duration)
    if not frame:IsShown() then
        frame.tweenValue = 0
        frame:SetAlpha(0)
        frame:Show()
    end
    UI.Tween(frame, 1, duration or 0.15, frame.SetAlpha)
end
