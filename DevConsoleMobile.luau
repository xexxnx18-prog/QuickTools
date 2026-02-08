local sg = cloneref(game:GetService("StarterGui"))
local pg = cloneref(game:GetService("Players")).LocalPlayer.PlayerGui

local ui = {
    button = {
        Size = UDim2.fromOffset(44,44),
        Position = UDim2.fromScale(1,1),
        AnchorPoint = Vector2.new(1,1),
        Text = "DC",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        BackgroundColor3 = Color3.fromRGB(18,18,18),
        TextColor3 = Color3.new(1,1,1),
        AutoButtonColor = false
    },
    stroke = {
        Thickness = 1,
        Color = Color3.fromRGB(80,80,80),
        Transparency = 0.15
    },
    gradient = {
        Rotation = 90,
        Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(45,45,45)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(10,10,10))
        }
    }
}

local g = Instance.new("ScreenGui", pg)
g.ResetOnSpawn = false

local b = Instance.new("TextButton", g)
for k,v in pairs(ui.button) do b[k] = v end
b.Position -= UDim2.fromOffset(10,10)

Instance.new("UICorner", b).CornerRadius = UDim.new(1,0)

local s = Instance.new("UIStroke", b)
for k,v in pairs(ui.stroke) do s[k] = v end

local gr = Instance.new("UIGradient", b)
for k,v in pairs(ui.gradient) do gr[k] = v end

b.MouseButton1Click:Connect(function()
    sg:SetCore("DevConsoleVisible", true)
end)