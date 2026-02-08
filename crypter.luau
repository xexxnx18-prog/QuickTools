--!strict

local sha256 = {}

local band = bit32.band
local bxor = bit32.bxor
local ror = bit32.rrotate
local rshift = bit32.rshift

local K = {
	0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
	0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
	0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
	0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
	0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
	0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
	0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
	0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
}

function sha256.hash(msg: string): string
	local H = {
		0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
		0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
	}

	local bytes = {string.byte(msg,1,#msg)}
	local bitlen = #bytes * 8
	bytes[#bytes+1] = 0x80
	while (#bytes % 64) ~= 56 do bytes[#bytes+1] = 0 end
	for i=7,0,-1 do bytes[#bytes+1] = band(rshift(bitlen,i*8),0xff) end

	for i=1,#bytes,64 do
		local w = {}
		for j=0,15 do
			local k=i+j*4
			w[j]=(bytes[k]<<24)|(bytes[k+1]<<16)|(bytes[k+2]<<8)|bytes[k+3]
		end
		for j=16,63 do
			local s0=bxor(ror(w[j-15],7),ror(w[j-15],18),rshift(w[j-15],3))
			local s1=bxor(ror(w[j-2],17),ror(w[j-2],19),rshift(w[j-2],10))
			w[j]=(w[j-16]+s0+w[j-7]+s1)%0x100000000
		end

		local a,b,c,d,e,f,g,h=table.unpack(H)
		for j=0,63 do
			local S1=bxor(ror(e,6),ror(e,11),ror(e,25))
			local ch=bxor(band(e,f),band(bxor(e,0xffffffff),g))
			local t1=(h+S1+ch+K[j+1]+w[j])%0x100000000
			local S0=bxor(ror(a,2),ror(a,13),ror(a,22))
			local maj=bxor(band(a,b),band(a,c),band(b,c))
			local t2=(S0+maj)%0x100000000
			h=g g=f f=e e=(d+t1)%0x100000000 d=c c=b b=a a=(t1+t2)%0x100000000
		end

		H[1]=(H[1]+a)%0x100000000
		H[2]=(H[2]+b)%0x100000000
		H[3]=(H[3]+c)%0x100000000
		H[4]=(H[4]+d)%0x100000000
		H[5]=(H[5]+e)%0x100000000
		H[6]=(H[6]+f)%0x100000000
		H[7]=(H[7]+g)%0x100000000
		H[8]=(H[8]+h)%0x100000000
	end

	return string.format(
		"%08x%08x%08x%08x%08x%08x%08x%08x",
		H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
	)
end

local function serialize(v, out)
	local t = typeof(v)
	if t == "number" or t == "boolean" then
		out[#out+1] = tostring(v)
	elseif t == "string" then
		out[#out+1] = v
	elseif t == "Vector3" then
		out[#out+1] = v.X.."|"..v.Y.."|"..v.Z
	elseif t == "CFrame" then
		local c = {v:GetComponents()}
		for i=1,#c do out[#out+1]=c[i] end
	elseif t == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys+1]=k end
		table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
		for _,k in ipairs(keys) do
			out[#out+1] = tostring(k)
			serialize(v[k],out)
		end
	else
		out[#out+1] = t
	end
end

function sha256.calc(v): string
	local buf = {}
	serialize(v,buf)
	return sha256.hash(table.concat(buf,"|"))
end

function sha256.calc_many(...): string
	local buf = {}
	for i=1,select("#",...) do
		serialize(select(i,...),buf)
	end
	return sha256.hash(table.concat(buf,"|"))
end

function sha256.roll(prev: string, v): string
	return sha256.hash(prev .. sha256.calc(v))
end

return sha256
