local mod = {}

local rss_template = [[
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
%s
</rss>
]]

mod.test_data = {
	feedURL = "https://example.com/rss",
	title = "Test Feed",
	link = "https://example.com",
	description = "Test feed description.",
	language = "en-us",
	posts = {
		{
			title = "Test Post",
			link = "https://example.com",
			description = "Test post description.",
			pubdate = "01-08-2025",
			guid = "https://example.com/exampleguid",
		},
		{
			title = "Test Post 2",
			link = "https://example.com",
			description = "Test post description 2.",
			pubdate = "01-08-2025",
		}
	}
}

function mod.rfc822datetime(time)
	return os.date("%a, %d %b %Y %X %Z", time)
end
function mod.dashdateToTimetable(input)
	local time = {
		month = input:sub(1, 2),
		day = input:sub(4, 5),
		year = input:sub(7, 10)
	}
	if input:len() > 10 then
		time.hour = input:sub(12, 13)
		time.min = input:sub(15, 16)
		if input:len() > 16 then
			time.sec = input:sub(18, 19)
		end
	end
	return time
end

local function sandwich(field, str)
	return "<" .. field .. ">" .. str .. "</" .. field .. ">"
end

function mod.exportRSS(input)
	assert(input.title and input.link and input.description)
	local ex_txt = {"<channel>"}
	local function add(indent, txt)
		table.insert(ex_txt, string.rep("  ", indent) .. txt)
	end
	add(1, sandwich("title", input.title))
	add(1, sandwich("link", input.link))
	if input.feedURL then
		add(1, ([[<atom:link href="%s" rel="self" type="application/rss+xml" />]]):format(input.feedURL))
	end
	add(1, sandwich("description", input.description))
	add(1,sandwich("language", input.language or "en-us"))

	for _, post in ipairs(input.posts) do
		assert(post.title and post.link and post.description)
		add(1, "<item>")
		add(2, sandwich("title", post.title))
		add(2, sandwich("link", post.link))
		add(2, sandwich("description", post.description))
		add(2, sandwich("pubDate", mod.rfc822datetime(os.time(mod.dashdateToTimetable(post.pubdate)))))
		add(2, sandwich("guid", post.guid or post.link))
		add(1, "</item>")
	end

	table.insert(ex_txt, "</channel>")
	return rss_template:format(table.concat(ex_txt, "\n"))
end

-- print(mod.exportRSS(test_data))
return mod