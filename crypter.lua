--!strict
--!native

local crypto = {}

local bxor = bit32.bxor
local band = bit32.band
local rshift = bit32.rshift
local rol = bit32.lrotate
local rand = Random.new()

local function u32(x)
	return band(x,0xffffffff)
end

local function bytes(s)
	local t={}
	for i=1,#s do t[i]=string.byte(s,i) end
	return t
end

local function str(t)
	local b={}
	for i=1,#t do b[i]=string.char(t[i]) end
	return table.concat(b)
end

local function nonce()
	return {
		rand:NextInteger(0,0xffffffff),
		rand:NextInteger(0,0xffffffff),
		rand:NextInteger(0,0xffffffff),
		rand:NextInteger(0,0xffffffff),
		rand:NextInteger(0,0xffffffff),
		rand:NextInteger(0,0xffffffff)
	}
end

local function keywords(k)
	local b=bytes(k)
	while #b<64 do b[#b+1]=0 end
	local o={}
	for i=1,16 do
		local p=(i-1)*4
		o[i]=b[p+1]*0x1000000+b[p+2]*0x10000+b[p+3]*0x100+b[p+4]
	end
	return o
end

local function blakeround(v,m)
	for i=1,12 do
		v[1]=u32(v[1]+v[2]+m[i]); v[4]=rol(bxor(v[4],v[1]),16)
		v[3]=u32(v[3]+v[4]); v[2]=rol(bxor(v[2],v[3]),12)
		v[1]=u32(v[1]+v[2]+m[i]); v[4]=rol(bxor(v[4],v[1]),8)
		v[3]=u32(v[3]+v[4]); v[2]=rol(bxor(v[2],v[3]),7)
	end
	return v
end

local function stretchkey(k,n)
	local v={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a}
	local m={}
	for i=1,16 do m[i]=bxor(k[i],n[(i-1)%6+1]) end
	local r=blakeround(v,m)
	local o={}
	for i=1,8 do o[i]=bxor(r[(i-1)%4+1],k[i]) end
	return o
end

local function q(a,b,c,d)
	a=u32(a+b); d=rol(bxor(d,a),16)
	c=u32(c+d); b=rol(bxor(b,c),12)
	a=u32(a+b); d=rol(bxor(d,a),8)
	c=u32(c+d); b=rol(bxor(b,c),7)
	return a,b,c,d
end

local function chachablock(k,n,c)
	local s={
		0x61707865,0x3320646e,0x79622d32,0x6b206574,
		k[1],k[2],k[3],k[4],
		k[5],k[6],k[7],k[8],
		c,n[1],n[2],n[3]
	}
	local w=table.clone(s)
	for i=1,10 do
		w[1],w[5],w[9],w[13]=q(w[1],w[5],w[9],w[13])
		w[2],w[6],w[10],w[14]=q(w[2],w[6],w[10],w[14])
		w[3],w[7],w[11],w[15]=q(w[3],w[7],w[11],w[15])
		w[4],w[8],w[12],w[16]=q(w[4],w[8],w[12],w[16])
		w[1],w[6],w[11],w[16]=q(w[1],w[6],w[11],w[16])
		w[2],w[7],w[12],w[13]=q(w[2],w[7],w[12],w[13])
		w[3],w[8],w[9],w[14]=q(w[3],w[8],w[9],w[14])
		w[4],w[5],w[10],w[15]=q(w[4],w[5],w[10],w[15])
	end
	for i=1,16 do w[i]=u32(w[i]+s[i]) end
	return w
end

local function stream(data,k,n)
	local out={}
	local ctr=1
	local i=1
	while i<=#data do
		local b=chachablock(k,n,ctr)
		ctr+=1
		for j=1,64 do
			if not data[i] then break end
			local w=b[math.ceil(j/4)]
			local sh=(3-(j-1)%4)*8
			out[i]=bxor(data[i],band(rshift(w,sh),255))
			i+=1
		end
	end
	return out
end

function crypto.encrypt(text,password)
	local n=nonce()
	local base=keywords(password)
	local k1=stretchkey(base,{n[1],n[2],n[3],n[4],n[5],n[6]})
	local k2=stretchkey(base,{n[6],n[5],n[4],n[3],n[2],n[1]})
	local k3=stretchkey(base,{bxor(n[1],n[4]),bxor(n[2],n[5]),bxor(n[3],n[6]),n[1],n[2],n[3]})
	local d=bytes(text)
	d=stream(d,k1,{n[1],n[2],n[3]})
	d=stream(d,k2,{n[4],n[5],n[6]})
	d=stream(d,k3,{n[2],n[3],n[4]})
	return str({
		n[1]%256,band(rshift(n[1],8),255),band(rshift(n[1],16),255),band(rshift(n[1],24),255),
		n[2]%256,band(rshift(n[2],8),255),band(rshift(n[2],16),255),band(rshift(n[2],24),255),
		n[3]%256,band(rshift(n[3],8),255),band(rshift(n[3],16),255),band(rshift(n[3],24),255),
		n[4]%256,band(rshift(n[4],8),255),band(rshift(n[4],16),255),band(rshift(n[4],24),255),
		n[5]%256,band(rshift(n[5],8),255),band(rshift(n[5],16),255),band(rshift(n[5],24),255),
		n[6]%256,band(rshift(n[6],8),255),band(rshift(n[6],16),255),band(rshift(n[6],24),255),
		table.unpack(d)
	})
end

return crypto