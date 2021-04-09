class('Dialog');

function Dialog:__init(title)
	self.title		= title or nil;
	self.buttons	= {};
	self.content	= nil;
end

function Dialog:__class()
	return 'Dialog';
end

function Dialog:AddButton(button, position, permission)
	if (button == nil or button['__class'] == nil) then
		-- Bad Item
		return;
	end
	
	if (button:__class() ~= 'Button') then
		-- Exception: Only Button
		return;
	end
	
	if position ~= nil then
	
	end
	
	if permission ~= nil then
		button:BindPermission(permission);
	end
	
	print(button:Serialize());
	
	table.insert(self.buttons, button);
end

function Dialog:SetContent(content)
	self.content = content;
end

function Dialog:Serialize(player)
	return {
		Title	= self.title,
		Content = self.content,
		Buttons	= self.buttons
	};
end

return Dialog;