local ADDON_NAME = "GuildsOfWoW"
local GOW = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME)
GuildsOfWow = GOW

local enableDebugging = false

GOW.consts = {}
GOW.consts.INVITE_INTERVAL = 3

local ns = select(2, ...)

local Core = {}
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("CALENDAR_NEW_EVENT")
f:RegisterEvent("CALENDAR_UPDATE_EVENT")
f:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
f:RegisterEvent("CALENDAR_UPDATE_GUILD_EVENTS")
f:RegisterEvent("CALENDAR_OPEN_EVENT")
f:RegisterEvent("CALENDAR_CLOSE_EVENT")
f:RegisterEvent("FRIENDLIST_UPDATE")
--f:RegisterEvent("CALENDAR_ACTION_PENDING")
f:RegisterEvent("CALENDAR_UPDATE_INVITE_LIST")
local isProcessing = false
local isPropogatingUpdate = false
local containerFrame = {}
local containerTabs = {}
local containerScrollFrame = {}

local currentCharName = ""
local currentCharRealm = ""

local showWindow = true
local isDialogOpen = false
local workQueue = nil

local currentEventsCount = 0
local currentMultiInvitingEvent = nil
local processedEvents = nil

local currentApplicationsCount = 0
local recruitmentCharacter = nil
local recruitmenNotes = nil

local copyText = ""

GOW.defaults = {
	profile = {
		version = 1,
        minimap = {hide = false}
    }
}

local selectedTab = "events";
local tabs = {
	{value = "events", text = "Upcoming Events" },
	{value = "recruitmentApps", text = "Recruitment Applications" },
}

function GOW:OnInitialize()
	self.GUI = LibStub("AceGUI-3.0")
	self.DB = LibStub("AceDB-3.0"):New("GoWDB", GOW.defaults, "Default")
	self.LDB = LibStub("LibDataBroker-1.1")
	self.LDBIcon = LibStub("LibDBIcon-1.0")
	self.CONSOLE = LibStub("AceConsole-3.0")
	self.timers = {}
	LibStub("AceTimer-3.0"):Embed(self.timers)
	self.events = {}
	LibStub("AceEvent-3.0"):Embed(self.events)
	workQueue = self.WorkQueue.new()
	processedEvents = GOW.List.new()
	
	local consoleCommandFunc = function(msg, editbox)
		if (msg == "minimap") then
			Core:ToggleMinimap()
		else
			Core:ToggleWindow()
		end
	end
	
	self.CONSOLE:RegisterChatCommand("gow", consoleCommandFunc);

	local dataobj = self.LDB:NewDataObject("gowicon", {
		type = "data source",
		label = "Guilds of WoW",
		text = "Guilds of WoW",
		icon = "Interface\\Icons\\vas_guildfactionchange",
		OnTooltipShow = function(tooltip)
			tooltip:SetText("Guilds of WoW")
			if (ns.UPCOMING_EVENTS ~= nil) then
				tooltip:AddDoubleLine("Upcoming Events", currentEventsCount)
			end
			if (ns.RECRUITMENT_APPLICATIONS ~= nil) then
				tooltip:AddDoubleLine("Recruitment Applications", currentApplicationsCount)
			end
			tooltip:Show()
		end,
		OnClick = function() Core:ToggleWindow() end
	})

	self.LDBIcon:Register("gowicon", dataobj, self.DB.profile.minimap);

	string.lpad = function(str, len, char)
		if char == nil then char = ' ' end
		return string.rep(char, len - #str) .. str
	end

	string.splitByDelimeter = function(str, delimiter)
		result = {};
		for match in (str..delimiter):gmatch("(.-)"..delimiter) do
			table.insert(result, match);
		end
		return result;
	end

	containerFrame = GOW.GUI:Create("Frame")
	containerFrame:SetLayout("Fill")
	containerFrame:SetHeight(550)
	containerFrame:SetTitle("Guilds of WoW")
	containerFrame:SetStatusText("Type /gow for quick access")
	containerFrame:SetCallback("OnClose", function(widget) containerFrame:Hide() end)
	containerFrame:SetCallback("OnEscapePressed", function(widget) containerFrame:Hide() end)
	--tinsert(UISpecialFrames, containerFrame:GetName())
	containerFrame:Hide()

	containerTabs = GOW.GUI:Create("TabGroup")
	containerTabs:SetTabs(tabs)
	containerTabs:SelectTab(selectedTab)
	containerTabs:SetCallback("OnGroupSelected", function(frame, event, value) Core:ToggleTabs(value) end)
	containerFrame:AddChild(containerTabs)

	containerScrollFrame = GOW.GUI:Create("ScrollFrame")
	containerScrollFrame:SetLayout("Flow")
	containerScrollFrame:SetFullWidth(true)
	containerScrollFrame:SetFullHeight(true)
	containerTabs:AddChild(containerScrollFrame)

	-- local closeButton = CreateFrame("Button", "$parentClose", f, "UIPanelCloseButton")
	-- closeButton:SetSize(24, 24)
	-- closeButton:SetPoint("TOPRIGHT")
	-- closeButton:SetScript("OnClick", function(self) self:GetParent():Hide() end)
	-- containerFrame:AddChild(closeButton)

	-- local close = CreateFrame("Button", nil, nil, "UIPanelCloseButton")
	-- close:SetPoint("TOPRIGHT", 2, 1)
	-- containerFrame:AddChild(close)

	if (ns.UPCOMING_EVENTS == nil or ns.RECRUITMENT_APPLICATIONS == nil) then
		print("|cffffff00Guilds of WoW: |cffFF0000Data is not fetched! Please make sure your sync app is installed and working properly.")
	end

	StaticPopupDialogs["CONFIRM_EVENT_CREATION"] = {
		text = "Are you sure you want to create this event on in-game calendar?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			C_Calendar.AddEvent()
			if(currentMultiInvitingEvent ~= nil) then
				Core:InviteMultiplePeopleToEvent()
			end
			Core:DialogClosed()			
		end,
		OnCancel = function ()
			currentMultiInvitingEvent = nil
			Core:DialogClosed()
			C_Calendar.CloseEvent()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["CONFIRM_INVITE_TO_GUILD"] = {
		text = "Are you sure you want to invite %s to your guild?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			GuildInvite(recruitmentCharacter)
			recruitmentCharacter = nil
			Core:DialogClosed()			
		end,
		OnCancel = function ()
			recruitmentCharacter = nil
			Core:DialogClosed()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["CONFIRM_ADD_FRIEND"] = {
		text = "Are you sure you want to add %s to your friend list?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			C_FriendList.AddFriend(recruitmentCharacter, recruitmenNotes)
			recruitmentCharacter = nil
			Core:DialogClosed()			
		end,
		OnCancel = function ()
			recruitmentCharacter = nil
			Core:DialogClosed()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 1
	  }

	  StaticPopupDialogs["WHISPER_PLAYER"] = {
		text = "Type your message",
		button1 = "Send",
		button2 = "Cancel",
		OnAccept = function(self, data, data2)
			local text = self.editBox:GetText()

			if (text ~= nil and text ~= "") then
				SendChatMessage(text, "WHISPER", nil, recruitmentCharacter);
				recruitmentCharacter = nil
				Core:DialogClosed()
			end
		end,
		OnCancel = function ()
			recruitmentCharacter = nil
			Core:DialogClosed()
		end,
		timeout = 100,
		enterClicksFirstButton = true,
		whileDead = true,
		hideOnEscape = true,
		hasEditBox  = true,
		preferredIndex = 3
	  }

	  StaticPopupDialogs["COPY_TEXT"] = {
		text = "Select & copy following text",
		button1 = "Done",
		OnShow = function (self, data)
			self.editBox:SetText(copyText)
			self.editBox:HighlightText()
		end,
		OnAccept = function()			
			Core:DialogClosed()
		end,
		timeout = 0,
		enterClicksFirstButton = true,
		whileDead = true,
		hideOnEscape = true,
		hasEditBox  = true,
		preferredIndex = 1
	  }
end

f:SetScript("OnEvent", function(self,event, arg1, arg2)
	if event == "PLAYER_LOGIN" then
		isProcessing = false

		local name, realm = UnitName("player")

		if (realm == nil) then
			realm = GetRealmName()
			--GetNormalizedRealmName()
		end

		currentCharName = name
		currentCharRealm = realm
	elseif event == "GUILD_ROSTER_UPDATE" then
		if (isProcessing == false) then
			Core:CreateRecruitmentApplications()
			Core:CreateUpcomingEvents()

			if (ns.UPCOMING_EVENTS ~= nil and ns.UPCOMING_EVENTS.totalEvents > 0) then
				Core:CheckEventInvites()
			end
		end
	elseif event == "CALENDAR_OPEN_EVENT" then
		local canAddEvent = true --C_Calendar.CanAddEvent()
		
		if (canAddEvent) then
			local eventInfo = C_Calendar.GetEventInfo()
			
			Core:Print("CALENDAR_OPEN_EVENT: Opened: " .. eventInfo.title)
			Core:ClearEventInvites(false)

			if (eventInfo.calendarType == "GUILD_EVENT" or eventInfo.calendarType == "PLAYER") then
				local upcomingEvent = Core:FindUpcomingEventFromName(eventInfo.title)

				if (upcomingEvent ~= nil and upcomingEvent.isManualInvite) then
					Core:CreateEventInvites(upcomingEvent)
				else
					Core:Print("Event invite refresh failed")
				end
			else 
				Core:Print("Not suitable calendar type")
			end
		end
	elseif event == "CALENDAR_NEW_EVENT" or event == "CALENDAR_UPDATE_EVENT" or event == "CALENDAR_UPDATE_EVENT_LIST" then
		Core:Print("CALENDAR_NEW_EVENT")
		if (isPropogatingUpdate == false and selectedTab == "events") then
			isPropogatingUpdate = true
			Core:CreateUpcomingEvents()
		end
	elseif event == "CALENDAR_CLOSE_EVENT" then
		Core:Print("CALENDAR_CLOSE_EVENT")
		Core:ClearEventInvites(true)
	elseif event == "CALENDAR_UPDATE_INVITE_LIST" then
		if (C_Calendar.IsEventOpen()) then
			local eventInfo = C_Calendar.GetEventInfo()

			if (eventInfo.title == "") then
				Core:ClearEventInvites(false)
			end
		end
	elseif event == "FRIENDLIST_UPDATE" then
		Core:Print("FRIENDLIST_UPDATE")
		Core:CreateRecruitmentApplications()
	end
end)

function Core:ToggleTabs(tabKey)
	selectedTab = tabKey
	Core:RefreshApplication()
end

function Core:RefreshApplication()
	isPropogatingUpdate = true
	isProcessing = false

	if (selectedTab == "events") then
		Core:CreateUpcomingEvents()
	elseif (selectedTab == "recruitmentApps") then
		Core:CreateRecruitmentApplications()
	end
end

function Core:ToggleWindow()
	if (containerFrame:IsShown()) then
		containerFrame:Hide()
	else
		Core:RefreshApplication()
		containerFrame:Show()
	end
end

function Core:CreateUpcomingEvents()
	if (ns.UPCOMING_EVENTS == nil) then
		currentEventsCount = 0
		containerScrollFrame:ReleaseChildren()
		Core:AppendMessage("Upcoming events data is not found! Please make sure your sync app is installed and working properly!", true)
	else
		local isInGuild = IsInGuild()

		if (isDialogOpen) then
			return
		end

		if (isInGuild == false) then
			isProcessing = true
			return
		end

		local guildName, _, _, realmName = GetGuildInfo("player")

		if (guildName == nil) then
			return
		end

		currentEventsCount = 0
		isProcessing = true
		containerScrollFrame:ReleaseChildren()

		if (realmName == nil) then
			realmName = GetRealmName()
		end

		local regionId = GetCurrentRegion()

		if (isInGuild and ns.UPCOMING_EVENTS.totalEvents > 0) then
			for i=1, ns.UPCOMING_EVENTS.totalEvents do
				local upcomingEvent = ns.UPCOMING_EVENTS.events[i]

				if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealm and regionId == upcomingEvent.guildRegionId) then
					Core:AppendCalendarList(upcomingEvent)
				end
			end
		end
	end

	showWindow = false
	isPropogatingUpdate = false
end

function Core:CreateRecruitmentApplications()
	if(ns.RECRUITMENT_APPLICATIONS == nil) then
		currentEventsCount = 0
		containerScrollFrame:ReleaseChildren()
		Core:AppendMessage("Recruitment applications data is not found! Please make sure your sync app is installed and working properly!", true)
	else
		local isInGuild = IsInGuild()

		if (isInGuild == false) then
			isProcessing = true
			return
		end

		local guildName, _, _, realmName = GetGuildInfo("player")

		if (guildName == nil) then
			return
		end

		currentApplicationsCount = 0
		isProcessing = true
		containerScrollFrame:ReleaseChildren()

		if (realmName == nil) then
			realmName = GetRealmName()
		end

		local regionId = GetCurrentRegion()

		if (isInGuild and ns.RECRUITMENT_APPLICATIONS.totalApplications > 0) then
			for i=1, ns.RECRUITMENT_APPLICATIONS.totalApplications do
				local recruitmentApplication = ns.RECRUITMENT_APPLICATIONS.recruitmentApplications[i]

				if (guildName == recruitmentApplication.guild and realmName == recruitmentApplication.guildRealm and regionId == recruitmentApplication.guildRegionId) then
					Core:AppendRecruitmentList(recruitmentApplication)
				end
			end

			--containerScrollFrame:DoLayout()
		end
	end
	showWindow = false
	isPropogatingUpdate = false
end

function Core:searchForEvent(event)
	local serverTime = GetServerTime()

	if (event.eventDate < serverTime) then
		return 0
	end

	C_Calendar.SetAbsMonth(event.month, event.year)

	local numDayEvents = C_Calendar.GetNumDayEvents(0, event.day)

	--Core:Print("events found: " .. numDayEvents .. " : " .. event.day .. "/" .. event.month .. "/" .. event.year)

	if (numDayEvents > 0) then
		for i=1, numDayEvents do
			local dayEvent = C_Calendar.GetDayEvent(0, event.day, i)
			
			if (dayEvent.calendarType == "GUILD_EVENT" or dayEvent.calendarType == "PLAYER") then
				--Core:Print("dayEvent: " .. dayEvent.title)

				if (string.match(dayEvent.title, "*" .. event.eventKey)) then
					return i
				end
			end
		end
	end

	return -1
end

function Core:AppendMessage(message, appendReloadUIButton)
	local fontPath = "Fonts\\FRIZQT__.TTF"
	local fontSize = 13

	local itemGroup = GOW.GUI:Create("SimpleGroup")
	--itemGroup:SetLayout("Line")
	itemGroup:SetFullWidth(true)
	itemGroup:SetFullHeight(true)

	local messageLabel = GOW.GUI:Create("Label")
	messageLabel:SetText(message)
	messageLabel:SetFullWidth(true)
	messageLabel:SetFont(fontPath, fontSize)
	itemGroup:AddChild(messageLabel)

	if(appendReloadUIButton) then
		local reloadUIButton = GOW.GUI:Create("Button")
		reloadUIButton:SetText("Reload UI")
		reloadUIButton:SetCallback("OnClick", function()
			ReloadUI()
		end)
		itemGroup:AddChild(reloadUIButton)
	end

	containerScrollFrame:AddChild(itemGroup)
end

function Core:AppendCalendarList(event)
	local itemGroup = GOW.GUI:Create("InlineGroup")
	itemGroup:SetTitle(event.title)
	itemGroup:SetFullWidth(true)

	local descriptionLabel = GOW.GUI:Create("SFX-Info")
	descriptionLabel:SetLabel("Description")
	descriptionLabel:SetText(event.description)
	-- descriptionLabel:SetCallback("OnEnter", function(widget)
	-- 	print("qwewerwer")
    --     GameTooltip:SetText("test test");
    --     GameTooltip:Show();
    -- end);
	itemGroup:AddChild(descriptionLabel)

	local dateLabel = GOW.GUI:Create("SFX-Info")
	dateLabel:SetLabel("Date")
	dateLabel:SetText(event.dateText)
	itemGroup:AddChild(dateLabel)

	local eventHourLabel = GOW.GUI:Create("SFX-Info")
	eventHourLabel:SetLabel("Hour")
	eventHourLabel:SetText(event.hourText)
	itemGroup:AddChild(eventHourLabel)

	local eventDurationLabel = GOW.GUI:Create("SFX-Info")
	eventDurationLabel:SetLabel("Duration")
	eventDurationLabel:SetText(event.durationText)
	itemGroup:AddChild(eventDurationLabel)
	
	local levelText = event.minLevel

	if event.minLevel ~= event.maxLevel then
		levelText = levelText .. " -> " .. event.maxLevel
	end

	local eventLevelLabel = GOW.GUI:Create("SFX-Info")
	eventLevelLabel:SetLabel("Level")
	eventLevelLabel:SetText(levelText)
	itemGroup:AddChild(eventLevelLabel)

	if (event.minItemLevel > 0) then
		local eventMinItemLevelLabel = GOW.GUI:Create("SFX-Info")
		eventMinItemLevelLabel:SetLabel("Item Level")
		eventMinItemLevelLabel:SetText(event.minItemLevel .. "+")
		itemGroup:AddChild(eventMinItemLevelLabel)
	end
	
	local isEventMember = false
	local canAddEvent = false --C_Calendar.CanAddEvent()

	for m=1, event.totalMembers do
		local currentInviteMember = event.inviteMembers[m]

		if (currentInviteMember.name == currentCharName and currentInviteMember.realm == currentCharRealm) then
			isEventMember = true
			canAddEvent = currentInviteMember.isManager
		end
	end

	local eventInvitingMembersLabel = GOW.GUI:Create("SFX-Info")
	eventInvitingMembersLabel:SetLabel("Inviting")

	local invitineDetailsText = ""

	if (event.isGuildEvent and event.minItemLevel == 0) then
		invitineDetailsText = "All guildies within level range"
	else 
		invitineDetailsText = event.totalMembers .. " members"
	end

	if (not isEventMember) then
		invitineDetailsText = invitineDetailsText .. " (You are not eligible for this event)"
	end

	eventInvitingMembersLabel:SetText(invitineDetailsText)
	itemGroup:AddChild(eventInvitingMembersLabel)

	local eventIndex = Core:searchForEvent(event)

	local buttonsGroup = GOW.GUI:Create("SimpleGroup")
	buttonsGroup:SetLayout("Flow")
	buttonsGroup:SetFullWidth(true)

	if (canAddEvent) then
		local eventButton = GOW.GUI:Create("Button")

		if eventIndex == 0 then
			eventButton:SetText("Event Passed")
			eventButton:SetDisabled(true)
		elseif eventIndex > 0 then
			eventButton:SetText("Event Created")
			eventButton:SetDisabled(true)
		else
			eventButton:SetText("Create In-Game Event")
			eventButton:SetCallback("OnClick", function()
				Core:CreateCalendarEvent(event)
			end)

			currentEventsCount = currentEventsCount + 1

			if (showWindow == true) then
				containerFrame:Show()
			end
		end
		buttonsGroup:AddChild(eventButton)
	end

	local copyLinkButton = GOW.GUI:Create("Button")
	copyLinkButton:SetText("Copy Link")
	copyLinkButton:SetWidth(140)
	copyLinkButton:SetCallback("OnClick", function()
		copyText = event.webUrl
		Core:OpenDialog("COPY_TEXT")
	end)
	buttonsGroup:AddChild(copyLinkButton)

	if (canAddEvent) then
		local copyKeyButton = GOW.GUI:Create("Button")
		copyKeyButton:SetText("Copy Key")
		copyKeyButton:SetWidth(140)
		copyKeyButton:SetCallback("OnClick", function()
			copyText = event.eventKey
			Core:OpenDialog("COPY_TEXT")
		end)
		buttonsGroup:AddChild(copyKeyButton)
	end

	itemGroup:AddChild(buttonsGroup)

	containerScrollFrame:AddChild(itemGroup)
end

function Core:AppendRecruitmentList(recruitmentApplication)
	local itemGroup = GOW.GUI:Create("InlineGroup")
	itemGroup:SetTitle(recruitmentApplication.title)
	itemGroup:SetFullWidth(true)

	local messageLabel = GOW.GUI:Create("SFX-Info")
	messageLabel:SetLabel("Message")
	messageLabel:SetText(recruitmentApplication.message)
	itemGroup:AddChild(messageLabel)

	local classLabel = GOW.GUI:Create("SFX-Info")
	classLabel:SetLabel("Class")
	classLabel:SetText(recruitmentApplication.classTitle)
	itemGroup:AddChild(classLabel)

	local dateLabel = GOW.GUI:Create("SFX-Info")
	dateLabel:SetLabel("Date")
	dateLabel:SetText(recruitmentApplication.dateText)
	itemGroup:AddChild(dateLabel)

	local buttonsGroup = GOW.GUI:Create("SimpleGroup")
	buttonsGroup:SetLayout("Flow")
	buttonsGroup:SetFullWidth(true)

	local inviteToGuildButton = GOW.GUI:Create("Button")
	inviteToGuildButton:SetText("Invite to Guild")
	inviteToGuildButton:SetWidth(140)
	inviteToGuildButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmTrimmed
		Core:OpenDialog("CONFIRM_INVITE_TO_GUILD", recruitmentApplication.title)
	end)
	buttonsGroup:AddChild(inviteToGuildButton)

	local inviteToPartyButton = GOW.GUI:Create("Button")
	inviteToPartyButton:SetText("Invite to Party")
	inviteToPartyButton:SetWidth(140)
	inviteToPartyButton:SetCallback("OnClick", function()
		C_PartyInfo.InviteUnit(recruitmentApplication.title .. "-" .. recruitmentApplication.realmTrimmed)
	end)
	buttonsGroup:AddChild(inviteToPartyButton)

	local friendInfo = C_FriendList.GetFriendInfo(recruitmentApplication.title)

	local addFriendButton = GOW.GUI:Create("Button")
	addFriendButton:SetText("Add Friend")
	addFriendButton:SetWidth(140)
	
	if (friendInfo ~= nil) then
		addFriendButton:SetDisabled(true)
	end

	addFriendButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmTrimmed
		recruitmenNotes = "Guilds of WoW recruitment"
		Core:OpenDialog("CONFIRM_ADD_FRIEND", recruitmentApplication.title)
	end)
	buttonsGroup:AddChild(addFriendButton)
	itemGroup:AddChild(buttonsGroup)

	local buttonsGroup2 = GOW.GUI:Create("SimpleGroup")
	buttonsGroup2:SetLayout("Flow")
	buttonsGroup2:SetFullWidth(true)

	local whisperButton = GOW.GUI:Create("Button")
	whisperButton:SetText("Whisper")
	whisperButton:SetWidth(140)
	whisperButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmTrimmed
		Core:OpenDialog("WHISPER_PLAYER")
	end)
	buttonsGroup2:AddChild(whisperButton)

	local copyButton = GOW.GUI:Create("Button")
	copyButton:SetText("Copy Link")
	copyButton:SetWidth(140)
	copyButton:SetCallback("OnClick", function()
		recruitmentCharacter = recruitmentApplication.title .. "-" .. recruitmentApplication.realmTrimmed
		copyText = recruitmentApplication.webUrl
		Core:OpenDialog("COPY_TEXT")
	end)
	buttonsGroup2:AddChild(copyButton)

	itemGroup:AddChild(buttonsGroup2)

	containerScrollFrame:AddChild(itemGroup)

	currentApplicationsCount = currentApplicationsCount + 1

	if (showWindow == true) then
		containerFrame:Show()
	end
end

function Core:OpenDialog(dialogName)
	isDialogOpen = true
	StaticPopup_Show(dialogName)
end
function Core:OpenDialog(dialogName, parameterStr)
	isDialogOpen = true
	StaticPopup_Show(dialogName, parameterStr)
end

function Core:DialogClosed()
	isDialogOpen = false
end

function Core:CreateCalendarEvent(event)
	if not workQueue:isEmpty() then
		print("|cffFF0000Another event is being formed right now! Please wait for a while and try again...")
		return
	end

	isDialogOpen = true
	local eventIndex = Core:searchForEvent(event)

	if eventIndex >= 0 then
		Core:DialogClosed()
		Core:Print("Event found or passed: " .. event.title)
	else
		Core:ClearEventInvites(false)
		C_Calendar.CloseEvent()
		C_Calendar.CreatePlayerEvent()
		C_Calendar.EventSetTitle(event.titleWithKey)
		C_Calendar.EventSetDescription(event.description)
		C_Calendar.EventSetType(event.eventType)
		C_Calendar.EventSetTime(event.hour, event.minute)
		C_Calendar.EventSetDate(event.month, event.day, event.year)

		currentMultiInvitingEvent = nil
		if (event.isGuildEvent and not event.isManualInvite) then
			C_Calendar.MassInviteGuild(event.minLevel, event.maxLevel, event.maxRank)
			Core:OpenDialog("CONFIRM_EVENT_CREATION")
		else
			currentMultiInvitingEvent = event
			Core:OpenDialog("CONFIRM_EVENT_CREATION")
		end
	end
end

function Core:InviteMultiplePeopleToEvent()
	if (currentMultiInvitingEvent ~= nil) then
		local event = currentMultiInvitingEvent

		local name, realm = UnitName("player")

		if (realm == nil) then
			realm = GetRealmName()
			--GetNormalizedRealmName()
		end

		local currentPlayer = name .. "-" .. realm

		local numInvites = C_Calendar.GetNumInvites()

		if (numInvites < event.totalMembers) then
			print("|cffffcc00Event invites are being sent in the background! Please wait for all events to complete before logging out.")

			for i=1, event.totalMembers do
				local currentInviteMember = event.inviteMembers[i]
				local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realm

				if (inviteName ~= currentPlayer) then
					workQueue:addTask(function() C_Calendar.EventInvite(inviteName) end, nil, GOW.consts.INVITE_INTERVAL)
				end
			end

			--Core:IsEventFormingEnded()
		end
	end
end

function Core:IsEventFormingEnded()
	if workQueue:isEmpty() then
		--print("|cff00ff00Event invites are completed.")
		Core:StartEventInvites()
	else
		GOW.timers:ScheduleTimer(function() Core:IsEventFormingEnded() end, 10)
	end
end

function Core:ClearEventInvites(restartInvites)
	currentMultiInvitingEvent = nil
	workQueue:clearTasks()
	Core:Print("Invites are canceled!")

	if (restartInvites) then
		Core:AddCheckEventsTask()
	end
end

function Core:AddCheckEventsTask()
	workQueue:addTask(function() 
		if (not C_Calendar.IsEventOpen()) 
			then 
				Core:CheckEventInvites() 
			else
				Core:AddCheckEventsTask()
		end
	end, nil, 30)
end

function Core:CheckEventInvites()
	Core:Print("Starting event invites!")

	local isInGuild = IsInGuild()

	if (isInGuild) then
		local isEventOpen = false --C_Calendar.IsEventOpen()

		if (not isEventOpen) then
			local guildName, _, _, realmName = GetGuildInfo("player")

			if (guildName == nil) then
				return
			end

			if (realmName == nil) then
				realmName = GetRealmName()
			end

			local regionId = GetCurrentRegion()

			for i=1, ns.UPCOMING_EVENTS.totalEvents do
				local upcomingEvent = ns.UPCOMING_EVENTS.events[i]

				if (not processedEvents:contains(upcomingEvent.titleWithKey) and upcomingEvent.isManualInvite and guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealm and regionId == upcomingEvent.guildRegionId) then
					local eventIndex = Core:searchForEvent(upcomingEvent)

					if (eventIndex > 0) then
						local dayEvent = C_Calendar.GetDayEvent(0, upcomingEvent.day, eventIndex)
						Core:Print(dayEvent.title .. " creator: " .. dayEvent.modStatus .. " eventIndex:" .. eventIndex)

						if (dayEvent.modStatus == "CREATOR" or dayEvent.modStatus == "MODERATOR") then
							Core:Print("Trying opening event: " .. upcomingEvent.titleWithKey)
							workQueue:addTask(function() C_Calendar.OpenEvent(0, upcomingEvent.day, eventIndex) end, nil, 3)
							return
							--Core:CreateEventInvites(upcomingEvent)
						else
							Core:Print("Not creator or moderator!")
						end
					end
				end
			end
		end
	end

	Core:Print("Check event invites completed!")
end

function Core:FindUpcomingEventFromName(eventTitle)
	Core:Print("Trying to find event from title: " .. eventTitle)
	local isInGuild = IsInGuild()

	if (isInGuild) then
		local guildName, _, _, realmName = GetGuildInfo("player")

		if (guildName == nil) then
			return
		end

		if (realmName == nil) then
			realmName = GetRealmName()
		end

		local regionId = GetCurrentRegion()

		for i=1, ns.UPCOMING_EVENTS.totalEvents do
			local upcomingEvent = ns.UPCOMING_EVENTS.events[i]

			if (guildName == upcomingEvent.guild and realmName == upcomingEvent.guildRealm and regionId == upcomingEvent.guildRegionId) then
				if (string.match(eventTitle, "*" .. upcomingEvent.eventKey)) then
					Core:Print("Upcoming event found: " .. upcomingEvent.title)
					return upcomingEvent
				end
			end
		end
	end

	return nil
end

function Core:CreateEventInvites(upcomingEvent)
	if (processedEvents:contains(upcomingEvent.titleWithKey)) then
		Core:Print("Processed queue contains event!")
		return false
	end

	local canSendInvite = C_Calendar.EventCanEdit()
	if (canSendInvite) then
		local invitesNum = C_Calendar.GetNumInvites()

		Core:Print("CreateEventInvites: " .. upcomingEvent.titleWithKey .. ". Currently invited members: " .. invitesNum)

		local invitedCount = 0

		for m=1, upcomingEvent.totalMembers do
			local currentInviteMember = upcomingEvent.inviteMembers[m]
			local inviteName = currentInviteMember.name .. "-" .. currentInviteMember.realm
			local isMemberInvited = false

			for a=1, invitesNum do
				local inviteInfo = C_Calendar.EventGetInvite(a)

				if (inviteInfo.name == currentInviteMember.name and inviteInfo.level == currentInviteMember.level and inviteInfo.classID == currentInviteMember.classId) then
					isMemberInvited = true
				end
			end

			if (not isMemberInvited) then
				Core:Print("Inviting: " .. inviteName .. "-"..currentInviteMember.level .."-"..currentInviteMember.classId)
				workQueue:addTask(function() C_Calendar.EventInvite(inviteName) end, nil, GOW.consts.INVITE_INTERVAL)
				
				invitedCount = invitedCount + 1
			end
		end

		if (invitedCount > 0) then
			Core:Print("CreateEventInvites Ended: " .. upcomingEvent.title .. ". Invited: " .. tostring(invitedCount))
			workQueue:addTask(function() Core:Print("Event invites completed: " .. upcomingEvent.titleWithKey) Core:SetAttendance(upcomingEvent) end, nil, 10)
		else 
			Core:SetAttendance(upcomingEvent)
		end
	else 
		Core:Print("Cannot invite to this event!")
	end
end

function Core:SetAttendance(upcomingEvent)
	if (processedEvents:contains(upcomingEvent.titleWithKey)) then
		Core:Print("Processed queue contains event!")
		return false
	end

	local canSendInvite = C_Calendar.EventCanEdit()
	if (canSendInvite) then
		local invitesNum = C_Calendar.GetNumInvites()

		Core:Print("SetAttendance: " .. upcomingEvent.titleWithKey .. ". Currently invited members: " .. invitesNum)

		local attendanceChangedCount = 0

		local currentEventAttendances = {}
		local attendanceIndex = 1

		for a=1, invitesNum do
			local inviteInfo = C_Calendar.EventGetInvite(a)
			--local responseTime = C_Calendar.EventGetInviteResponseTime(a)

			if (inviteInfo.inviteStatus > 1) then
				currentEventAttendances[attendanceIndex] = {
					name = inviteInfo.name,
					level = inviteInfo.level,
					attendance = inviteInfo.inviteStatus,
					classId = inviteInfo.classID,
					guid = inviteInfo.guid,
					--responseTime = responseTime.year .. "-" .. string.lpad(tostring(responseTime.month), 2, '0') .. "-" .. string.lpad(tostring(responseTime.monthDay), 2, '0') .. "T" .. string.lpad(tostring(responseTime.hour), 2, '0') .. ":" .. string.lpad(tostring(responseTime.minute), 2, '0')
				}

				attendanceIndex = attendanceIndex + 1
			end
			
			for m=1, upcomingEvent.totalMembers do
				local currentInviteMember = upcomingEvent.inviteMembers[m]
	
				if (currentInviteMember.isManager or currentInviteMember.attendance > 1) then
					if (inviteInfo.name == currentInviteMember.name and inviteInfo.level == currentInviteMember.level and inviteInfo.classID == currentInviteMember.classId) then
						local isInvitationChanged = false

						if (currentInviteMember.isManager) then
							if (inviteInfo.modStatus ~= "CREATOR" and inviteInfo.modStatus ~= "MODERATOR") then
								isInvitationChanged = true
								Core:Print("Setting member as moderator: " .. upcomingEvent.title .. ". Title: " .. inviteInfo.name)
								workQueue:addTask(function() C_Calendar.EventSetModerator(a) end, nil, GOW.consts.INVITE_INTERVAL)
							end
						end

						if (currentInviteMember.attendance > 1 and inviteInfo.inviteStatus == 1) then
							isInvitationChanged = true
							Core:Print("Setting member attendance: " .. upcomingEvent.title .. ". Title: " .. inviteInfo.name .. ". GoWAttendance: " .. tostring(currentInviteMember.attendance) .. ". In-Game Attendance: " .. tostring(inviteInfo.inviteStatus))
							workQueue:addTask(function() C_Calendar.EventSetInviteStatus(a, currentInviteMember.attendance - 1) end, nil, GOW.consts.INVITE_INTERVAL)
						end
					
						if (isInvitationChanged) then
							attendanceChangedCount = attendanceChangedCount + 1
						end
					end
				end
			end
		end

		if (GOW.DB.profile.guilds == nil) then
			GOW.DB.profile.guilds = {}
		end

		local guildKey = upcomingEvent.guild .. "-" .. upcomingEvent.guildRealm

		if (GOW.DB.profile.guilds[guildKey] == nil) then
			GOW.DB.profile.guilds[guildKey] = { }
		end

		if (GOW.DB.profile.guilds[guildKey].events == nil) then
			GOW.DB.profile.guilds[guildKey].events = { }
		end

		local eventId = tostring(upcomingEvent.id)

		if (GOW.DB.profile.guilds[guildKey].events[eventId] == nil) then
			GOW.DB.profile.guilds[guildKey].events[eventId] = { }
		end

		if (GOW.DB.profile.guilds[guildKey].events[eventId].attendances == nil) then
			GOW.DB.profile.guilds[guildKey].events[eventId].attendances = { }
		end

		GOW.DB.profile.guilds[guildKey].events[eventId].attendances = currentEventAttendances

		if (attendanceChangedCount > 0) then
			Core:Print("SetAttendance Ended: " .. upcomingEvent.title .. ". SetAttendance: " .. tostring(attendanceChangedCount))
			workQueue:addTask(function() Core:Print("Event attendances completed: " .. upcomingEvent.titleWithKey) processedEvents:push(upcomingEvent.titleWithKey) C_Calendar.CloseEvent() end, nil, 10)
		else 
			processedEvents:push(upcomingEvent.titleWithKey)
			C_Calendar.CloseEvent()
		end
	else 
		Core:Print("Cannot set attendance to this event!")
	end
end

function Core:ToggleMinimap()
	GOW.DB.profile.minimap.hide = not GOW.DB.profile.minimap.hide
	if GOW.DB.profile.minimap.hide then
		GOW.LDBIcon:Hide("gowicon");
	else
		GOW.LDBIcon:Show("gowicon");
	end
end

function Core:Print(msg)
	if (enableDebugging) then
		print("|cffffcc00" .. msg)
	end
end