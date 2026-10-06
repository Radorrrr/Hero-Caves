local NumberFormatter = {}
local suffixes = {"", "K", "M", "B", "T"}

function NumberFormatter.Format(value)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return "—"
	end
	local magnitude = math.abs(value)
	if magnitude < 1000 then
		return string.format("%.0f", value)
	end
	local index = 1
	local divisor = 1
	while magnitude / divisor >= 1000 and index < #suffixes do
		index += 1
		divisor *= 1000
	end
	local rounded = math.floor(magnitude / divisor * 10 + 0.5) / 10
	if rounded >= 1000 and index < #suffixes then
		index += 1
		rounded /= 1000
	end
	local text = string.format("%.1f", value < 0 and -rounded or rounded):gsub("%.0$", "")
	return text .. suffixes[index]
end

return NumberFormatter
