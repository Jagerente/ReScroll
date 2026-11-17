local _, ns = ...

ns.CLASS_BUFFS = {
    fortitude = {
        { spell = 1243, level = 1, amount = 4, single = true },
        { spell = 1244, level = 12, amount = 10, single = true },
        { spell = 1245, level = 24, amount = 26, single = true },
        { spell = 2791, level = 36, amount = 42, single = true },
        { spell = 10937, level = 48, amount = 56, single = true },
        { spell = 21562, level = 48, amount = 56, single = false },
        { spell = 10938, level = 60, amount = 70, single = true },
        { spell = 21564, level = 60, amount = 70, single = false },
    },
    intellect = {
        { spell = 1459, level = 1, amount = 2, single = true },
        { spell = 1460, level = 14, amount = 7, single = true },
        { spell = 1461, level = 28, amount = 15, single = true },
        { spell = 10156, level = 42, amount = 22, single = true },
        { spell = 10157, level = 56, amount = 31, single = true },
        { spell = 23028, level = 56, amount = 31, single = false },
    },
    divineSpirit = {
        { spell = 14752, level = 30, amount = 17, single = true },
        { spell = 14818, level = 40, amount = 23, single = true },
        { spell = 14819, level = 50, amount = 33, single = true },
        { spell = 27681, level = 60, amount = 40, single = false },
        { spell = 27841, level = 60, amount = 40, single = true },
    },
}
