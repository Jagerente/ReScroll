local _, ns = ...

SLASH_RESCROLL1 = "/scrolls"
SLASH_RESCROLL2 = "/rescroll"
SlashCmdList.RESCROLL = function()
    ns.Options.Toggle()
end

function ReScroll_OnAddonCompartmentClick()
    ns.Options.Toggle()
end
