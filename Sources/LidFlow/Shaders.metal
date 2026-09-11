#include <metal_stdlib>
using namespace metal;
struct Raster { float4 position [[position]]; float2 uv; };
struct Params { float progress; float perspective; float blur; float shadow; float style; float aspect; float handoff; float prefiltered; };

float random2(float2 p) { return fract(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
float overlayOpacity(constant Params &p) { return p.handoff>.5 ? smoothstep(0.0f,.012f,p.progress) : 1.0f; }
float foldAngle(constant Params &p) { return clamp(p.progress,0.0f,1.0f)*p.perspective*(p.style>2.5 ? .42f : 1.25663706f); }
float2 projectUV(float2 uv,constant Params &p) {
    float phi=foldAngle(p),v=1-uv.y,k=1.8/(1.8+v*sin(phi));
    return float2(.5+(uv.x-.5)*k,1-v*cos(phi)*k);
}
float2 ashGrid(constant Params &p) {
    float columns=floor(mix(144.0f,76.0f,p.shadow));
    return float2(columns,ceil(columns/max(p.aspect,.5f)));
}
float ashOnset(float2 cell,float2 grid) {
    float2 center=(cell+.5)/grid;
    // A ragged front travels diagonally down the desktop, leaving its lower
    // left corner intact longest. Fixed seeds make reversing the lid reversible.
    float front=.035+center.y*.40+(1-center.x)*.14+random2(cell)*.11;
    float border=min(min(center.x,1-center.x),min(center.y,1-center.y));
    float edgeFront=.025+.13*center.y+random2(cell+7.3)*.13;
    return mix(edgeFront,front,smoothstep(0.0f,.075f,border));
}
vertex Raster foldVertex(uint i [[vertex_id]]) {
    const float2 points[] = {float2(-1,1),float2(-1,-1),float2(1,1),float2(1,-1)};
    Raster r; r.position=float4(points[i],0,1); r.uv=float2((points[i].x+1)*.5,(1-points[i].y)*.5); return r;
}
fragment float4 foldFragment(Raster in [[stage_in]], constant Params &p [[buffer(0)]],
    texture2d<float> original [[texture(0)]], texture2d<float> soft [[texture(1)]],
    texture2d<float> medium [[texture(2)]], texture2d<float> heavy [[texture(3)]]) {
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    float amount=clamp(p.progress,0.0f,1.0f),opacity=overlayOpacity(p);
    // Exact identity and the existing transparent handoff apply to every style.
    if(amount < .00005) return float4(original.sample(s,in.uv).rgb*opacity,opacity);
    float phi=foldAngle(p),D=1.8,r=1-in.uv.y,denom=D*cos(phi)-r*sin(phi);
    if(denom <= .0001) return float4(0,0,0,opacity);
    float v=r*D/denom,k=D/(D+v*sin(phi));
    float2 uv=float2((in.uv.x-.5)/k+.5,1-v);
    // Evaluate silhouette coverage before clamping texture coordinates. Its
    // filter extends beyond the projected plane, just like the image's blur.
    float coverage=1;
    if(p.style<2.5) {
        float h=clamp(1-uv.y,0.0f,1.0f);
        float radius=amount*.045;
        float2 q=abs(float2((uv.x-.5)*p.aspect,uv.y-1))-float2(p.aspect*.5-radius,1-radius);
        float distance=length(max(q,float2(0)))+min(max(q.x,q.y),0.0f)-radius;
        float aa=max(fwidth(distance)*.7,.00001f);
        float materialWidth=p.style<.5 ? .11f : (p.style<1.5 ? .075f : .15f);
        float softness=amount*p.blur*materialWidth*(.35+.65*h);
        float width=max(aa,softness);
        coverage=1-smoothstep(-width,width,distance);
        if(coverage<=0) return float4(0,0,0,opacity);
    } else if(any(uv<0)||any(uv>1)) return float4(0,0,0,opacity);
    uv=clamp(uv,0.0f,1.0f);
    float h=1-uv.y;
    float3 c=original.sample(s,uv).rgb;
    if(p.style>2.5) {
        float2 grid=ashGrid(p),cell=min(floor(uv*grid),grid-1);
        float onset=ashOnset(cell,grid);
        float intact=1-smoothstep(onset,onset+.035,amount);
        // Warm, desaturated fracture edge before the original pixels detach.
        float edge=smoothstep(onset-.06,onset,amount)*intact;
        float luma=dot(c,float3(.2126,.7152,.0722));
        c=mix(c,float3(luma)*float3(1.10,.91,.76),edge*.45);
        return float4(c*intact*opacity,opacity);
    }
    if(p.style<.5) {
        // Silk: a continuous satin light ribbon and gentle, depth-dependent focus.
        float focus=1-exp(-amount*p.blur*3.0);
        c=mix(c,soft.sample(s,uv).rgb,focus*smoothstep(.12,.7,h));
        c=mix(c,medium.sample(s,uv).rgb,focus*smoothstep(.55,1.0,h)*.65);
        float ribbon=exp(-pow((h-(.48+.17*uv.x-.12*amount))/.21,2.0f));
        float sheen=amount*(.12+.34*ribbon)*smoothstep(0.0f,.3f,h);
        c=1-(1-c)*(1-float3(.88,.97,1.0)*sheen);
        c*=1-amount*p.shadow*(.72*pow(h,1.3f)+.25*pow(abs(uv.x-.5)*2,2.0f));
    } else if(p.style<1.5) {
        // Shade: crisp ink-like content under a broad directional shadow.
        float focus=1-exp(-amount*p.blur*3.0);
        float3 defocused=mix(soft.sample(s,uv).rgb,medium.sample(s,uv).rgb,smoothstep(.2,.9,h));
        c=mix(c,defocused,focus*(.4+.6*h));
        float directional=.3+.7*smoothstep(.05,.92,h+.16*uv.x);
        float occlusion=amount*p.shadow*1.6*directional;
        float3 ink=c*float3(.79,.86,1.0);
        c=mix(c,ink,amount*.5)*exp(-occlusion*2.6);
        float rim=exp(-pow(uv.y/.016,2.0f))*amount*.08;
        c+=float3(.65,.73,.85)*rim;
    } else {
        // Frost: diffuse milky glass, refracted detail and a stable fine grain.
        float frost=1-exp(-amount*p.blur*4.0);
        float2 grainCell=floor(uv*float2(1100,1100/max(p.aspect,.5f)));
        float noise=random2(grainCell)-.5;
        float2 refract=float2(noise,random2(grainCell+19.3)-.5)*amount*p.blur*.014;
        float3 diffuse=mix(medium.sample(s,uv+refract).rgb,heavy.sample(s,uv+refract).rgb,.45+.5*h);
        c=mix(c,diffuse,frost);
        float milk=amount*(.55+.30*h);
        c=mix(c,float3(.78,.89,.95),milk);
        c+=noise*amount*.065;
        c*=exp(-amount*p.shadow*1.5*(.1+.9*pow(h,1.5f)));
        c+=float3(.11,.16,.19)*amount*exp(-pow(uv.y/.025,2.0f));
    }
    return float4(clamp(c,0.0f,1.0f)*coverage*opacity,opacity);
}

struct AshRaster {
    float4 position [[position]];
    float2 uv;
    float age;
    float alpha;
    float seed;
    float3 barycentric;
};
vertex AshRaster ashVertex(uint vertexID [[vertex_id]],uint instanceID [[instance_id]],constant Params &p [[buffer(0)]]) {
    float2 grid=ashGrid(p);
    uint cellID=instanceID/2,halfID=instanceID%2;
    float2 cell=float2(cellID%uint(grid.x),cellID/uint(grid.x));
    const float2 corners[]={float2(0,0),float2(1,0),float2(0,1),float2(1,0),float2(1,1),float2(0,1)};
    float2 corner=corners[halfID*3+vertexID];
    float2 origin=(cell+.5)/grid;
    float onset=ashOnset(cell,grid);
    float elapsed=max(0.0f,p.progress-onset);
    float age=clamp(elapsed/.30f,0.0f,1.0f);
    float seed=random2(cell+float(halfID)*31.7);
    float wind=.4+1.2*p.blur;
    float2 drift=float2(.09+.28*seed,-.10-.24*random2(cell+8.1))*wind*pow(age,1.25f);
    drift+=float2(sin(age*8+seed*6)-sin(seed*6),cos(age*6+seed*9)-cos(seed*9))*.025*age;
    float rotation=(seed-.5)*age*10;
    float2 offset=(corner-.5)/grid;
    // Rotate in physical screen coordinates so a shard keeps its proportions.
    offset.x*=p.aspect;
    offset=float2(cos(rotation)*offset.x-sin(rotation)*offset.y,sin(rotation)*offset.x+cos(rotation)*offset.y);
    offset.x/=p.aspect;
    offset*=1-.96*smoothstep(.05,1.0,age);
    float2 screen=projectUV(origin+offset,p)+drift;
    AshRaster out;
    out.position=float4(screen.x*2-1,1-screen.y*2,0,1);
    out.uv=(cell+corner)/grid;
    out.age=age;out.seed=seed;
    out.barycentric=vertexID==0 ? float3(1,0,0) : (vertexID==1 ? float3(0,1,0) : float3(0,0,1));
    out.alpha=smoothstep(onset,onset+.035,p.progress)*(1-smoothstep(.5,1.0,age))*overlayOpacity(p);
    if(cell.y>=grid.y || p.progress<=onset) out.alpha=0;
    return out;
}
fragment float4 ashFragment(AshRaster in [[stage_in]],texture2d<float> original [[texture(0)]]) {
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    float3 c=original.sample(s,in.uv).rgb;
    float luma=dot(c,float3(.2126,.7152,.0722));
    float3 ash=float3(luma)*float3(1.15,.96,.80)+float3(.11,.075,.04);
    c=mix(c,ash,smoothstep(0.0f,.6f,in.age))*(.8+.35*in.seed);
    // Analytic edge coverage reduces sparkle when tiny shards cross pixels.
    float3 coverage=smoothstep(float3(0),max(fwidth(in.barycentric),float3(.0001)),in.barycentric);
    float alpha=in.alpha*min(coverage.x,min(coverage.y,coverage.z));
    return float4(c*alpha,alpha);
}
