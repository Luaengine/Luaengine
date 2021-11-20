file={}
if scrupp.PLATFORM=="Windows" then
	file.dirs=function(a)
		local b=io.popen([[dir "]]..core.dir()..a..[[" /b /ad]])
		local c=b:read("*a")b:close()
		return string.explode(c,"\n")
	end
elseif scrupp.PLATFORM=="Linux" then
	file.dirs=function(a)return{"example"}end
elseif scrupp.PLATFORM=="Mac OS X" then
else exit()end
file.exists=function(a)
	local b=io.open(core.dir()..a,"r")
	if b~=nil then io.close(b)
	return true else
	return false end
end
file.read=function(a)
	local b=io.open(core.dir()..a,"r")
	if b~=nil then
		local c=b:read("*a")
		io.close(b)return c
	else return""end
end
file.write=function(a,b)
	local c=io.open(core.dir()..a,"w")
	if c~=nil then
		c:write(tostring(b))
		io.close(c)
	end
end
file.append=function(a,b)
	local c=io.open(core.dir()..a,"a")
	if c~=nil then
		c:write(tostring(b))
		io.close(c)
	end
end
file.size=function(a)
	local b=io.open(core.dir()..a,"r")
	if b~=nil then
		local c=b:seek("end")
		io.close(b)return c
	else return 0 end
end