//!PARAM STANDARD
//!DESC Video standard: NTSC (640x480, YIQ) or PAL (768x576, YUV).
//!TYPE ENUM DEFINE
NTSC
PAL

//!PARAM TAPE_AGE
//!DESC Oxide shedding and binder decay: dropouts, chroma noise, faded color, lifted blacks. 0 fresh, 1 decades old.
//!TYPE CONSTANT float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.15

//!PARAM TAPE_WEAR
//!DESC Mechanical abrasion and stretch: luma snow and capstan wow/flutter. 0 like-new, 1 thrashed.
//!TYPE CONSTANT float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.18

//!PARAM HEAD_ALIGNMENT
//!DESC Head azimuth error: HF luma/chroma rolloff and deeper line shimmer. 0 aligned, 1 badly off.
//!TYPE CONSTANT float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.12

//!PARAM HEAD_WEAR
//!DESC Worn/clogged video head with weak RF: reduced bandwidth, grain, wider aperture, streaky dropouts. 0 sharp, 1 worn.
//!TYPE CONSTANT float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.15

//!PARAM TRACKING
//!DESC Servo tracking: per-line time-base jitter, head-switch tear, sync slips. 0 locked, 1 bad.
//!TYPE CONSTANT float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.08

//!PARAM GENERATION
//!DESC Analogue dub count; each copy compounds bandwidth loss, color bleed, noise. 1 master, 5 copy-of-a-copy.
//!TYPE CONSTANT float
//!MINIMUM 1.0
//!MAXIMUM 5.0
1.0

//!PARAM SYNC_STABILITY
//!DESC Vertical-sync lock: lower periodically loses lock and rolls/shears. 1 never rolls, ~0 rolls violently.
//!TYPE CONSTANT float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.92

//!PARAM SPEED
//!DESC Global time multiplier for all animated effects. Below 1 slower, above 1 faster.
//!TYPE CONSTANT float
//!MINIMUM 0.1
//!MAXIMUM 3.0
0.65

//!PARAM RECORDING_MODE
//!DESC Recording mode: SP (best), LP, EP/SLP. PAL has no EP — use LP at most there.
//!TYPE ENUM DEFINE
SP
LP
EP

//!PARAM SCAN_FORMAT
//!DESC Scan format: INTERLACED (field weave, motion combing, head A/B shimmer) or PROGRESSIVE.
//!TYPE ENUM DEFINE
INTERLACED
PROGRESSIVE

//!PARAM GHOSTING
//!DESC Off-air multipath: faint displaced luma echo (trailing reflection + weak leader). 0 none, 1 strong.
//!TYPE CONSTANT float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.0


//!HOOK MAIN
//!BIND HOOKED
//!WIDTH 640 128 STANDARD * +
//!HEIGHT 480 96 STANDARD * +
//!SAVE VHS1
//!DESC VHS pass 1: downscale, RGB->Y/C, bandwidth limit, multipath ghost

#if STANDARD == PAL
#define TEXEL vec2(1.0 / 768.0, 1.0 / 576.0)
#else
#define TEXEL vec2(1.0 / 640.0, 1.0 / 480.0)
#endif
#define TAPE_SPEED (float(RECORDING_MODE) * 0.5)

float rgb2y(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec2 rgb2c(vec3 c) {
#if STANDARD == PAL
    return vec2(dot(c, vec3(-0.14713, -0.28886,  0.43601)),
                dot(c, vec3( 0.61500, -0.51499, -0.10001)));
#else
    return vec2(dot(c, vec3(0.595716, -0.274453, -0.321263)),
                dot(c, vec3(0.211456, -0.522591,  0.311135)));
#endif
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    float gen01 = clamp((GENERATION - 1.0) / 4.0, 0.0, 1.0);

#if SCAN_FORMAT == INTERLACED
    float fieldParity = mod(floor(uv.y / TEXEL.y), 2.0);
    float headBW = fieldParity * (HEAD_WEAR * 0.6 + HEAD_ALIGNMENT * 0.4);
#else
    float headBW = 0.0;
#endif

    float lumaSigma = 0.5 + HEAD_ALIGNMENT * 0.7 + HEAD_WEAR * 0.5 + gen01 * 0.5 + headBW * 0.35 + TAPE_SPEED * 1.0;
    float inv2s2 = 1.0 / (2.0 * lumaSigma * lumaSigma);
    float yCenter = rgb2y(HOOKED_tex(uv).rgb);
    float yLp1 = rgb2y(HOOKED_tex(uv + vec2(TEXEL.x, 0.0)).rgb);
    float yLm1 = rgb2y(HOOKED_tex(uv - vec2(TEXEL.x, 0.0)).rgb);
    float yL = yCenter;
    float lw = 1.0;
    for (int k = 0; k < 5; k++) {
        float i0 = float(2 * k + 1), i1 = float(2 * k + 2);
        float w0 = exp(-i0 * i0 * inv2s2), w1 = exp(-i1 * i1 * inv2s2);
        float wsum = w0 + w1;
        if (wsum < 1e-20) break;
        float off = (i0 * w0 + i1 * w1) / wsum;
        yL += rgb2y(HOOKED_tex(uv + vec2( off * TEXEL.x, 0.0)).rgb) * wsum;
        yL += rgb2y(HOOKED_tex(uv + vec2(-off * TEXEL.x, 0.0)).rgb) * wsum;
        lw += 2.0 * wsum;
    }
    yL /= lw;
    yL += (yCenter - (yLp1 + yLm1) * 0.5) * (0.40 + gen01 * 0.25);

    if (GHOSTING > 0.001) {
        float gD = (18.0 + 3.0 * sin(float(frame) * SPEED * 0.011 + 1.3)) * TEXEL.x;
        float yGhost = (rgb2y(HOOKED_tex(uv - vec2(gD, 0.0)).rgb)
                      + rgb2y(HOOKED_tex(uv - vec2(gD + TEXEL.x, 0.0)).rgb)) * 0.5;
        float yPre = rgb2y(HOOKED_tex(uv + vec2(8.0 * TEXEL.x, 0.0)).rgb);
        float g1 = GHOSTING * 0.09, g0 = GHOSTING * 0.025;
        yL = (yL + g1 * yGhost + g0 * yPre) / (1.0 + g1 + g0);
    }

    float chromaSigma = 5.0 + HEAD_ALIGNMENT * 5.0 + gen01 * 5.0 + TAPE_SPEED * 1.5;
    float chromaInv2s2 = 1.0 / (2.0 * chromaSigma * chromaSigma);
    float delayPx = 4.0 + gen01 * 4.0 + HEAD_WEAR * 2.0 + TAPE_SPEED * 3.0;
    vec2 uvC = uv - vec2(delayPx * TEXEL.x, 0.0);
    vec2 cc = rgb2c(HOOKED_tex(uvC).rgb);
    float cw = 1.0;
    for (int k = 0; k < 14; k++) {
        float i0 = float(2 * k + 1), i1 = float(2 * k + 2);
        float w0 = exp(-i0 * i0 * chromaInv2s2), w1 = exp(-i1 * i1 * chromaInv2s2);
        float wsum = w0 + w1;
        if (wsum < 1e-5 * cw) break;
        float off = (i0 * w0 + i1 * w1) / wsum;
        cc += rgb2c(HOOKED_tex(uvC + vec2( off * TEXEL.x, 0.0)).rgb) * wsum;
        cc += rgb2c(HOOKED_tex(uvC + vec2(-off * TEXEL.x, 0.0)).rgb) * wsum;
        cw += 2.0 * wsum;
    }
    cc /= cw;
    cc *= clamp(1.0 - TAPE_AGE * 0.20 - gen01 * 0.08 - TAPE_SPEED * 0.06, 0.50, 1.0);

    return vec4(yL, cc, 1.0);
}


//!HOOK MAIN
//!BIND VHS1
//!BIND FIELDS
//!WIDTH 640 128 STANDARD * +
//!HEIGHT 480 96 STANDARD * +
//!SAVE VHS1
//!WHEN SCAN_FORMAT !
//!DESC VHS field weave: refresh this frame's field, hold the other from the previous frame

vec4 hook() {
    vec2 uv = VHS1_pos;
    float rowPar = mod(floor(uv.y / VHS1_pt.y), 2.0);
    float frmPar = mod(float(frame), 2.0);
    return abs(rowPar - frmPar) < 0.5 ? VHS1_tex(uv) : FIELDS_tex(uv);
}


//!HOOK MAIN
//!BIND VHS1
//!WIDTH 640 128 STANDARD * +
//!HEIGHT 480 96 STANDARD * +
//!SAVE FIELDS
//!WHEN SCAN_FORMAT !
//!DESC VHS field store for the next frame's weave

vec4 hook() { return VHS1_tex(VHS1_pos); }


//!HOOK MAIN
//!BIND VHS1
//!WIDTH 640 128 STANDARD * +
//!HEIGHT 480 96 STANDARD * +
//!SAVE VHS2
//!DESC VHS pass 2: roll/jitter/slip geometry, dot crawl, fringing, color kill, Hanover bars, noise, dropouts

#define TEXEL VHS1_pt
#define TAPE_SPEED (float(RECORDING_MODE) * 0.5)
const float PI  = 3.14159265;
const float TAU = 6.28318531;
const float ROLL_DRIFT  = 0.06;
const float ROLL_WOBBLE = 0.07;
#if STANDARD == PAL
#define FSC_CYCLES    283.7516
#define HUE_ERR_SCALE 0.2
#define PILOT_SCALE   0.3
#else
#define FSC_CYCLES    227.5
#define HUE_ERR_SCALE 1.0
#define PILOT_SCALE   1.0
#endif

float h21(vec2 p) {
    uvec2 q = floatBitsToUint(p + vec2(131.0, 1031.0));
    uint n = (q.x * 1597334677u) ^ (q.y * 3812015801u);
    n = (n ^ (n >> 16)) * 2246822519u;
    n = (n ^ (n >> 13)) * 3266489917u;
    n = n ^ (n >> 16);
    return float(n) * (1.0 / 4294967296.0);
}
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = h21(i),                b = h21(i + vec2(1.0, 0.0)),
          c = h21(i + vec2(0.0, 1.0)), d = h21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float vnoiseT(vec2 p, float t) {
    float t0 = floor(t), tf = fract(t);
    tf = tf * tf * (3.0 - 2.0 * tf);
    return mix(vnoise(p + t0 * 13.7), vnoise(p + (t0 + 1.0) * 13.7), tf);
}

float subcarrierPhase(float x01, float scanline, float frm) {
#if STANDARD == PAL
    return TAU * (FSC_CYCLES * x01 + 0.7516 * scanline + 0.25 * frm);
#else
    return TAU * FSC_CYCLES * x01 + PI * (scanline + frm);
#endif
}

float bandStatic(float sx, float scanline, float frm) {
    vec2 p = vec2(sx / TEXEL.x + frm * 31.7, scanline + frm * 0.47);
    return (h21(p) + h21(p + 71.3)) * 0.5;
}

float bandBoil(float sx, float scanline, float frm, float t) {
    return clamp(vnoiseT(vec2(sx * 130.0, scanline + frm * 0.47), t * 6.0) * 1.1
               + (bandStatic(sx, scanline, frm) - 0.5) * 0.5, 0.0, 1.0);
}

vec4 hook() {
    vec2 uv = VHS1_pos;
    float frm = float(frame);
    float t = frm * SPEED;
    float gen01 = clamp((GENERATION - 1.0) / 4.0, 0.0, 1.0);

    float tWow = t * 0.0052, tFlut = t * 0.0210, tJit = t * 0.1300, tHead = t * 0.0330, tSync = t * 0.0080;

    float instab = 1.0 - SYNC_STABILITY;
    float stress = instab * (0.35 + TRACKING * 0.15 + HEAD_WEAR * 0.10);
    float syncField = vnoiseT(vec2(0.0, 5.0), tSync) * 0.6 + vnoiseT(vec2(0.0, 9.0), tSync * 2.3) * 0.4;
    float sHold = syncField + stress * 0.5;
    float loss = smoothstep(0.88, 0.97, sHold) * smoothstep(0.30, 0.60, instab);
    float rollOsc = 0.6 + 0.4 * sin(tSync * TAU * 1.7 + 1.0);
    float contPhase = ROLL_DRIFT * (0.6 * t - 4.681 * cos(tSync * TAU * 1.7 + 1.0)) + 0.5 * sin(t * ROLL_WOBBLE);
    float rollable = step(0.32, instab);
    float rollOn = step(0.90, sHold) * rollable;
    float rollPhase = fract(contPhase);
    float rollOffset = rollOn * (rollPhase - 0.75 * sin(TAU * rollPhase) * (1.0 / TAU));
    float rollSlewRate = rollOn * (1.0 - 0.75 * cos(TAU * rollPhase))
                       * (ROLL_DRIFT * rollOsc * SPEED + 0.5 * ROLL_WOBBLE * SPEED * cos(t * ROLL_WOBBLE));
    float slewMag = abs(rollSlewRate) + loss * 0.01;
    float breathe = (vnoiseT(vec2(0.0, 71.0), tFlut) - 0.5) * TAPE_WEAR * 1.4 * TEXEL.y;
    float settle = smoothstep(0.84, 0.90, sHold) * (1.0 - rollOn) * rollable
                 * sin((0.90 - sHold) * 240.0) * 4.0 * TEXEL.y;
    float rolledY = fract(uv.y + breathe + rollOffset + settle);
    float line = rolledY / TEXEL.y;
    float scanline = floor(line);
    float fieldParity = mod(scanline, 2.0);
#if STANDARD == PAL
    float palSwitch = fieldParity * 2.0 - 1.0;
#endif

    float wob = 0.6 + 0.4 * sin(t * 0.05 + 3.0);
    float topFall = 1.0 - smoothstep(0.0, 0.4, rolledY);
    float skew = topFall * (1.0 + 0.4 * topFall) * sqrt(loss) * (0.10 + 0.08 * wob);

    float wow = TAPE_WEAR * 0.6 + TRACKING * 0.4;
    float swow = (sin(uv.y * 6.3  + tWow * TAU) * 0.0016
                + sin(uv.y * 11.7 + tFlut * TAU) * 0.0009
                + sin(uv.y * 19.1 + tWow * 3.1 + 1.7) * 0.0006) * wow;
    float jline = (vnoiseT(vec2(line * 0.15, 0.0), tJit) - 0.5) * 0.0042 * TRACKING;
    float yHere = VHS1_tex(vec2(uv.x, rolledY)).r;
    float yPrev = VHS1_tex(vec2(uv.x - 2.0 * TEXEL.x, rolledY)).r;
    float sigJit = (yHere - yPrev) * (0.0016 + TAPE_SPEED * 0.0016) * (0.5 + TRACKING);
    float jitter = swow + jline + sigJit;

    float stretch = (sin(uv.y * 9.4 + tWow * TAU * 1.3 + 0.7) * 0.0012
                   + sin(uv.y * 15.2 + tFlut * TAU * 0.8) * 0.0006) * wow * (1.0 + TAPE_SPEED * 0.5);
    jitter += stretch * uv.x;

    float pllBend = (vnoiseT(vec2(3.0, 17.0), t * 1.1) - 0.5) * 0.05 * exp(-rolledY * 18.0);
    float pllTear = (vnoiseT(vec2(scanline * 0.9 + 7.3, 0.0), t * 2.3) - 0.5) * 0.025 * exp(-rolledY * 55.0);
    float preEq   = (vnoiseT(vec2(scanline * 0.7 + 41.0, 5.0), t * 1.9) - 0.5) * 0.012 * exp(-(1.0 - rolledY) * 90.0);
    jitter += (pllBend + pllTear + preEq) * loss;

    float hsCenter = 0.972 + (vnoise(vec2(tHead, 7.0)) - 0.5) * 0.012;
    float hsZone = smoothstep(hsCenter - 0.03, hsCenter - 0.005, rolledY)
                 * (1.0 - smoothstep(hsCenter + 0.015, hsCenter + 0.04, rolledY));
    float hsAmt = 0.006 + TRACKING * 0.022 + HEAD_WEAR * 0.010;
    jitter += hsZone * ((vnoiseT(vec2(line * 0.3, 3.0), tJit * 1.3) - 0.5) * hsAmt + 0.004);

    float ewScale = (TAPE_WEAR * 0.5 + TAPE_AGE * 0.2 + TAPE_SPEED * 0.25) * 0.006;
    jitter += ((vnoiseT(vec2(uv.y * 3.2, 19.0),      tWow * 0.7) - 0.5) * 0.9
             + (vnoiseT(vec2(uv.y * 6.7 + 7.0, 43.0), tFlut * 0.5) - 0.5) * 0.1) * ewScale;

    float tnHunt = 0.30 + 0.70 * vnoiseT(vec2(3.0, 61.0), tSync * 1.7);
    float tnBand = 0.022 + (TRACKING * 0.55 + HEAD_WEAR * 0.20 + TAPE_SPEED * 0.25) * 0.055;
    float tnRelY = rolledY - hsCenter
                 + (vnoiseT(vec2(scanline * 0.9, 47.0), t * 2.6) - 0.5) * tnBand * 0.5;
    float tnDepth = smoothstep(-tnBand * 1.10, tnBand * 0.10, tnRelY); tnDepth *= tnDepth;
    float tnLumaDepth = smoothstep(-tnBand * 0.12, tnBand * 0.10, tnRelY); tnLumaDepth *= tnLumaDepth;
    float tnWave = vnoiseT(vec2(scanline * 0.04, 29.0), t * 0.25) - 0.5;
    float hookT = smoothstep(hsCenter - tnBand, 1.0, rolledY);
    float tnTearMag = (0.008 + TRACKING * 0.035 + TAPE_SPEED * 0.012)
                    * (0.6 + 0.8 * vnoiseT(vec2(7.0, 37.0), t * 0.5)) * hookT * hookT
                    * (1.0 + (vnoiseT(vec2(scanline * 0.45 + 61.0, 17.0), t * 0.55) - 0.5) * 0.7);
    jitter += tnWave * (TRACKING * 0.45 + TAPE_SPEED * 0.18) * 0.018 * tnDepth - tnTearMag;

    float slipShift = 0.0, slipIntensity = 0.0, slipCrawlMul = 1.0, slipChromaRot = 0.0;
    float maxSlipOn = 0.0, primarySlipY = 0.5, primarySlipHt = 0.08, slipGrain = 0.0, slipBWMask = 0.0;
    float slipBase = clamp(TRACKING * 0.45 + HEAD_WEAR * 0.30 + TAPE_WEAR * 0.15, 0.0, 1.0);
    if (slipBase > 0.02) {
        for (int si = 0; si < 2; si++) {
            float sf = float(si);
            float thresh = mix(0.975, 0.595, slipBase) + sf * (1.0 - slipBase) * 0.30;
            float slipNoise = vnoiseT(vec2(sf * 3.73, 0.0), tSync * 0.34)
                            + (vnoiseT(vec2(sf * 17.0, 3.0), tSync * 1.6) - 0.5) * 0.05;
            float slipOn = smoothstep(thresh, thresh + 0.05, slipNoise) * slipBase;
            if (slipOn < 0.001) continue;

            float slipDrift = vnoise(vec2(11.0, tSync * 0.09));
            float slipY  = 0.10 + fract(slipDrift * 0.35 + t * 0.0006 + sf * 0.45) * 0.80;
            float slipHt = 0.04 + vnoise(vec2(sf * 2.17, tSync * 0.19 + sf * 5.43)) * 0.12;
            if (slipOn > maxSlipOn) { maxSlipOn = slipOn; primarySlipY = slipY; primarySlipHt = slipHt; }

            float gGate = step(0.40, vnoise(vec2(sf * 9.3, floor(tSync * 0.20) + sf * 2.7)));
            float gHt = (0.003 + vnoise(vec2(sf * 5.7, floor(tSync * 0.30) + sf)) * 0.010) * slipOn * gGate;
            float gBot = slipY + slipHt * 0.03
                       + (vnoiseT(vec2(scanline * 0.80 + sf * 17.0, sf * 3.0), tJit * 0.9) - 0.5) * gHt * 2.0;
            slipGrain = max(slipGrain, smoothstep(gBot - gHt * 0.5, gBot + gHt * 0.5, rolledY)
                                     * (1.0 - smoothstep(gBot + gHt * 0.5, gBot + gHt * 1.5, rolledY)));

            float above = smoothstep(slipY - slipHt, slipY - slipHt * 0.15, rolledY);
            float below = 1.0 - smoothstep(slipY - slipHt * 0.08, slipY + slipHt * 0.03, rolledY);
            float inBand = above * below * slipOn;
            if (inBand < 0.001) continue;

            float slipLow  = vnoiseT(vec2(scanline * 0.11 + sf * 31.0, sf * 11.3), tJit * 0.55) - 0.5;
            float slipHigh = (vnoiseT(vec2(scanline * 0.95 + sf * 73.0, sf * 23.0), tJit * 2.40) - 0.5) * 0.55;
            slipShift += (slipLow + slipHigh) * (0.045 + slipBase * 0.05) * inBand;
            slipIntensity = max(slipIntensity, inBand);

            float bwGate = step(0.74, vnoise(vec2(sf * 4.1, floor(tSync * 0.25) + sf * 3.3)));
            slipBWMask = max(slipBWMask, inBand * bwGate);
            slipCrawlMul = mix(slipCrawlMul, 1.0 + 4.0 * slipBase, inBand);

            float rotSign = vnoise(vec2(sf * 13.7, floor(tSync * 0.50 + sf * 1.3))) > 0.5 ? 1.0 : -1.0;
            slipChromaRot += inBand * 1.2 * sin(scanline * 0.35 * rotSign + t * 0.31);

            float flagDir = vnoise(vec2(sf * 11.3, floor(tSync * 0.15) + sf * 2.1)) > 0.5 ? 1.0 : -1.0;
            float edgeRamp = above * smoothstep(slipY - slipHt, slipY + slipHt * 0.03, rolledY)
                           * (1.0 - smoothstep(slipY + slipHt * 0.03, slipY + slipHt * 0.18, rolledY));
            slipShift += (vnoiseT(vec2(scanline * 0.45 + sf * 43.0, sf * 7.0), tJit * 0.85) - 0.5)
                       * flagDir * 0.06 * edgeRamp * slipOn;
        }
        jitter += slipShift;
    }

    float rawX = uv.x + jitter + skew;
    vec2 suv = vec2(fract(rawX), rolledY);
    float blank = 1.0 - step(0.0, rawX) * step(rawX, 1.0);

    float ycV = loss * (0.012 + 1.6 * slewMag) * sin(tSync * TAU * 0.7 + 2.0);
    float ycH = loss * (0.004 + 0.6 * slewMag) + slipIntensity * (0.07 + TRACKING * 0.06);
    vec2 cuv = vec2(fract(suv.x + ycH + tnTearMag * 0.55), fract(rolledY + ycV));

    vec3 sig;
    sig.x  = VHS1_tex(suv).r;
    sig.yz = VHS1_tex(cuv).yz;

    float ph = subcarrierPhase(suv.x, scanline, frm);
    vec3 up1 = VHS1_tex(clamp(suv - vec2(0.0, TEXEL.y), 0.0, 1.0)).rgb;
    vec2 car;
    float combResid;
#if STANDARD == PAL
    float crawlAmt = (0.10 + gen01 * 0.08 + TAPE_SPEED * 0.08) * slipCrawlMul;
    sig.yz = mix(sig.yz, up1.yz, 0.5);
    car = vec2(sin(ph), palSwitch * cos(ph));
    combResid = dot(sig.yz - up1.yz, car);
#else
    float crawlAmt = (0.18 + gen01 * 0.10 + TAPE_SPEED * 0.10) * slipCrawlMul;
    car = vec2(cos(ph), sin(ph));
    vec3 up2 = VHS1_tex(clamp(suv - vec2(0.0, 2.0 * TEXEL.y), 0.0, 1.0)).rgb;
    combResid = dot(sig.yz - mix(up1.yz, up2.yz, 0.35), car);
#endif
    sig.x += combResid * 0.5 * crawlAmt;
    float yHF = sig.x - VHS1_tex(clamp(suv + vec2(TEXEL.x, 0.0), 0.0, 1.0)).r;
    sig.yz += yHF * car * (crawlAmt * 0.8);

    float fr = TEXEL.x * (6.0 + gen01 * 4.0 + TAPE_SPEED * 3.0);
    vec2 cL = VHS1_tex(clamp(suv - vec2(fr, 0.0), 0.0, 1.0)).yz;
    vec2 cR = VHS1_tex(clamp(suv + vec2(fr, 0.0), 0.0, 1.0)).yz;
    float edge = max(clamp(length(cR - cL) * 3.0, 0.0, 1.0), clamp(abs(yHF) * 4.0, 0.0, 1.0));
    float sat = clamp(length(sig.yz) * 2.5, 0.0, 1.0);
    sig.yz += ((cL + cR) - 2.0 * sig.yz) * (1.8 + gen01 * 1.5) * edge;
    sig.yz += (cL - sig.yz) * 0.25 * edge * sqrt(sat);

    sig.x = mix(sig.x, 0.025, blank);
    sig.yz *= 1.0 - blank;

    float bar = (1.0 - smoothstep(0.0, 0.02, min(rolledY, 1.0 - rolledY))) * loss;
    sig.x = mix(sig.x, 0.02, bar) + bar * (vnoiseT(uv * vec2(240.0, 160.0), t * 3.0) - 0.5) * 0.5;
    sig.yz = mix(sig.yz, vec2(0.0), bar);
    if (bar > 0.01) {
        float d = rolledY < 0.5 ? rolledY : rolledY - 1.0;
        float serr = step(abs(d + 0.006), 0.003) * step(0.5, fract(suv.x * 6.0));
#if STANDARD == PAL
        float cc = step(abs(d - 0.014), 0.004)
                 * step(0.55, vnoiseT(vec2(suv.x * 24.0, scanline * 0.9), frm * 0.5));
#else
        float cc = step(abs(d - 0.014), 0.0016)
                 * step(0.55, vnoiseT(vec2(suv.x * 24.0, 3.0), frm * 0.5));
#endif
        sig.x += loss * (serr * 0.28 + cc * 0.5);
    }
    sig.yz *= 1.0 - smoothstep(0.50, 0.88, loss);

    float hueErr = ((vnoiseT(vec2(line * 0.2, 1.0), tJit * 0.8) - 0.5) * 0.25 * loss
                  + (pllBend + pllTear) * 12.0 * loss + jline * 9.0) * HUE_ERR_SCALE;
#if STANDARD == NTSC
    hueErr += (clamp(sig.x, 0.0, 1.0) - 0.35) * (0.05 + gen01 * 0.10 + TAPE_AGE * 0.05);
#endif

    if (slipIntensity > 0.001) {
        sig.x += (vnoiseT(vec2(suv.x / TEXEL.x + frm * 17.3, scanline + frm * 0.31), t * 13.0) - 0.5) * 0.18 * slipIntensity;
        float ghostSeg = smoothstep(0.72, 0.86, vnoiseT(vec2(suv.x * 4.0 + scanline * 0.5, scanline * 0.09 + 27.0), tJit * 1.1))
                       * slipIntensity;
        if (ghostSeg > 0.001) {
            float gx = fract(suv.x + (vnoiseT(vec2(scanline * 0.2, 53.0), tJit) - 0.5) * 0.2);
            sig.x = mix(sig.x, VHS1_tex(vec2(gx, fract(rolledY + TEXEL.y))).r, ghostSeg);
        }
        float segLoss = smoothstep(0.55, 0.80, vnoiseT(vec2(suv.x * 6.0 + scanline * 0.7, scanline * 0.13 + 9.0), tJit * 1.6))
                      * slipIntensity * (0.5 + slipBase * 0.5);
        sig.x = mix(sig.x, bandBoil(suv.x, scanline, frm, t), segLoss);
        sig.yz *= 1.0 - clamp(segLoss * 2.2, 0.0, 1.0) * 0.9;
    }
    float bandSat = 1.0 - smoothstep(0.30, 0.62, slipIntensity);
    sig.yz *= (1.0 - slipBWMask) * bandSat;

    if (slipGrain > 0.001) {
        sig.x = mix(sig.x, bandBoil(suv.x, scanline, frm, t), slipGrain * 0.85);
        sig.yz *= 1.0 - slipGrain;
        float gHue = h21(vec2(scanline * 0.713 + 5.0, frm * 0.37)) * TAU;
        sig.yz += vec2(cos(gHue), sin(gHue)) * 0.12 * slipGrain;
    }

    float ckBase = clamp(TRACKING * 0.60 + HEAD_WEAR * 0.50 + TAPE_WEAR * 0.25 - 0.20, 0.0, 1.0);
    if (ckBase > 0.01 && maxSlipOn > 0.20) {
        float ckEvent = step(1.0 - ckBase * 0.45, vnoiseT(vec2(0.0, 53.7), tSync * 0.22))
                      * smoothstep(slipBase * 0.55, slipBase * 0.85, maxSlipOn);
        float bwMask = ckEvent * step(rolledY, primarySlipY + primarySlipHt * 0.03);
        sig.yz *= 1.0 - bwMask;
        if (bwMask > 0.001)
            sig.x = clamp(sig.x + (bandStatic(suv.x, scanline, frm) - 0.5) * 0.05 * bwMask, 0.0, 1.2);
    }

    float pilot = ((vnoiseT(vec2(scanline * 0.09, 5.0), t * 0.17) - 0.5) * 0.05
                 + (vnoiseT(vec2(scanline * 0.23, 9.0), t * 0.29) - 0.5) * 0.02)
                * PILOT_SCALE * (0.5 + TAPE_AGE * 0.5 + HEAD_WEAR * 0.4 + gen01 * 0.3);
#if STANDARD == NTSC && SCAN_FORMAT == INTERLACED
    pilot += (fieldParity - 0.5) * (HEAD_ALIGNMENT * 0.12 + TRACKING * 0.04);
#endif
    pilot += hsZone * (0.25 + TRACKING * 0.35) * (0.6 + 0.4 * sin(tHead * TAU * 2.3));
    float phErr = hueErr + slipChromaRot + pilot;
    float pc = cos(phErr), ps = sin(phErr);
    sig.yz = mat2(pc, -ps, ps, pc) * sig.yz;

#if STANDARD == PAL
    float satNow = length(sig.yz);
    float hanoverAmt = (TRACKING * 0.24 + HEAD_WEAR * 0.15 + TAPE_AGE * 0.09)
                     * (1.0 - 0.65 * smoothstep(0.25, 0.55, satNow));
    float hanoverBand = sin(line * 0.9 + (vnoiseT(vec2(line * 0.05, 31.0), tJit * 0.5) - 0.5) * 8.0);
    sig.yz *= max(0.0, 1.0 + hanoverBand * hanoverAmt);
#endif

    sig.yz *= 1.0 + (vnoiseT(vec2(line * 0.05, 23.0), tHead * 0.6) - 0.5) * (0.06 + TRACKING * 0.45 + HEAD_WEAR * 0.25);

#if SCAN_FORMAT == INTERLACED
    float headNoise = 1.0 + (fieldParity - 0.5) * (0.25 + HEAD_WEAR * 0.5);
    sig.x *= 1.0 + (fieldParity - 0.5) * (HEAD_WEAR * 0.025 + HEAD_ALIGNMENT * 0.012);
#else
    float headNoise = 1.0;
#endif
    float lumaNoiseAmt = (0.022 + TAPE_WEAR * 0.055 + HEAD_WEAR * 0.045 + TAPE_AGE * 0.028 + gen01 * 0.028 + TAPE_SPEED * 0.07)
                       * headNoise * (1.0 + slipIntensity * 3.6);
    float lumaN = (vnoiseT(vec2(uv.x * 70.0, scanline),         t * 2.1) - 0.5) * 0.7
                + (vnoiseT(vec2(uv.x * 35.0, scanline + 200.0), t * 1.3) - 0.5) * 0.3;
    sig.x += lumaN * lumaNoiseAmt * mix(1.2, 0.45, smoothstep(0.0, 0.5, sig.x));

    float burstRate = TAPE_WEAR * 0.03 + HEAD_WEAR * 0.02 + TAPE_AGE * 0.01 + TAPE_SPEED * 0.01;
    if (burstRate > 0.001) {
        float burstAcc = 0.0;
        for (int bi = 0; bi < 3; bi++) {
            vec2 bseed = vec2(scanline * 0.431 + float(bi) * 97.3, frm * 0.173 + float(bi) * 43.7);
            if (h21(bseed) < burstRate) {
                float bx0 = h21(bseed + vec2(17.3, 61.1));
                float dt = (suv.x - bx0) / (0.012 + h21(bseed + vec2(53.9, 23.7)) * 0.038);
                if (dt >= 0.0 && dt <= 1.0)
                    burstAcc = max(burstAcc, smoothstep(0.0, 0.07, dt) * (1.0 - dt) * (1.0 - dt));
            }
        }
        float shadowBoost = mix(1.1, 0.7, smoothstep(0.0, 0.5, sig.x));
        sig.x = mix(sig.x, min(sig.x + 0.35, 1.0), clamp(burstAcc * burstRate * 10.0 * shadowBoost, 0.0, 0.80));
    }

    float tnBase = min(clamp(0.18 + TRACKING * 0.55 + TAPE_SPEED * 0.22, 0.0, 1.0)
                       * tnHunt * (1.0 + maxSlipOn * 0.5), 1.0);
    float tnOpacity = tnDepth * tnBase;
    if (tnOpacity > 0.01) {
        float tnDragX = suv.x + tnWave * tnDepth * 0.55;
        float harsh = bandBoil(tnDragX, scanline, frm, t);
        float lineLvl = vnoiseT(vec2(scanline * 1.7, 83.0), t * 3.1);
        float tnLoss = clamp(tnLumaDepth * tnBase * (0.35 + 0.65 * lineLvl), 0.0, 1.0) * (1.0 - blank);
        sig.x = mix(sig.x, harsh, tnLoss);
        float tnKill = clamp(tnLoss * 2.2, 0.0, 1.0) * (0.85 + TRACKING * 0.15);
        sig.yz *= 1.0 - tnKill;
        float lineHue = h21(vec2(scanline * 0.713, frm * 0.37)) * TAU;
        float cAmp = vnoiseT(vec2(scanline * 0.3 + 3.7, 11.0), tHead) * 0.8 + 0.2;
        float hVar = (vnoiseT(vec2(suv.x * 1.2, scanline * 0.08 + 7.0), tHead * 0.4) - 0.5) * 0.3;
        float cSeg = smoothstep(0.40, 0.70, vnoiseT(vec2(tnDragX * 9.0 + scanline * 0.6,
                                                         scanline * 0.21 + 19.0), tHead * 0.7));
        sig.yz += vec2(cos(lineHue + hVar), sin(lineHue + hVar)) * cAmp * cSeg
                * tnOpacity * 0.85 * (1.0 - tnKill * 0.9) * (1.0 - blank);
    }

    float chromaNoiseAmt = (0.050 + TAPE_AGE * 0.09 + gen01 * 0.045 + TAPE_SPEED * 0.05)
                         * (1.0 + slipIntensity * 4.5 * bandSat)
                         * (0.30 + 0.70 * smoothstep(0.0, 0.35, sig.x));
    vec2 cn = vec2(vnoiseT(vec2(suv.x * 40.0,       scanline * 0.5),         t * 0.6),
                   vnoiseT(vec2(suv.x * 40.0 + 5.0, scanline * 0.5 + 100.0), t * 0.4));
    sig.yz += (cn - 0.5) * chromaNoiseAmt;

    if (h21(vec2(scanline * 0.137, frm * 0.431)) < TAPE_AGE * 0.12 + TAPE_WEAR * 0.05 + TAPE_SPEED * 0.04)
        sig.yz = up1.yz;

    float baseRate = TAPE_AGE * 0.7 + HEAD_WEAR * 0.5 + TAPE_SPEED * 0.4;
    float burstGate = mix(0.35, 1.0, smoothstep(0.35, 0.70, vnoise(vec2(t * 0.020, 11.3))));
    float doRand = vnoiseT(vec2(line * 1.7 + 31.0, 0.0), t * 0.18 + 50.0) * 0.6
                 + vnoiseT(vec2(line * 4.3 + 71.0, 0.0), t * 0.27 + 90.0) * 0.4;
    float doHit = smoothstep(0.92 - baseRate * 0.11 * burstGate, 0.97 - baseRate * 0.11 * burstGate, doRand);
    if (doHit > 0.001) {
        float xc = vnoise(vec2(line * 2.3 + 13.0, floor(t * 0.18)));
        float len = 0.03 + 0.22 * vnoise(vec2(line * 3.1 + 47.0, 5.0));
        float seg = smoothstep(xc - 0.01, xc + 0.005, uv.x)
                  * (1.0 - smoothstep(xc + len - 0.02, xc + len + 0.02, uv.x)) * doHit;
        float lift = 0.4 + TAPE_AGE * 0.4;
        sig.x  = mix(sig.x, mix(up1.r, 1.0, lift), seg);
        sig.yz = mix(sig.yz, vec2(0.0), seg);
    }

    return vec4(sig, 1.0);
}


//!HOOK MAIN
//!BIND VHS2
//!WIDTH 640 128 STANDARD * +
//!HEIGHT 480 96 STANDARD * +
//!SAVE VHS3
//!DESC VHS pass 3: luma peaking + ringing + IIR smear, chroma comet tail

#define TEXEL VHS2_pt
#define TAPE_SPEED (float(RECORDING_MODE) * 0.5)

vec4 hook() {
    vec2 uv = VHS2_pos;
    float gen01 = clamp((GENERATION - 1.0) / 4.0, 0.0, 1.0);

    vec4 c   = VHS2_tex(uv);
    vec4 nm4 = VHS2_tex(uv + vec2(-4.0 * TEXEL.x, 0.0));
    vec4 nm3 = VHS2_tex(uv + vec2(-3.0 * TEXEL.x, 0.0));
    vec4 nm2 = VHS2_tex(uv + vec2(-2.0 * TEXEL.x, 0.0));
    vec4 nm1 = VHS2_tex(uv + vec2(-1.0 * TEXEL.x, 0.0));
    vec4 np1 = VHS2_tex(uv + vec2( 1.0 * TEXEL.x, 0.0));
    vec4 np2 = VHS2_tex(uv + vec2( 2.0 * TEXEL.x, 0.0));

    float peak = c.r - (nm2.r + nm1.r + np1.r + np2.r) * 0.25;
    c.r = clamp(c.r + peak * (0.6 + gen01 * 0.3), 0.0, 1.2);
    float ringAmt = (HEAD_WEAR * 0.35 + HEAD_ALIGNMENT * 0.25 + gen01 * 0.20) * 0.45;
    c.r = clamp(c.r - (np1.r - nm2.r) * ringAmt * 1.2, 0.0, 1.2);

    float smearAmt = TAPE_SPEED * 0.25 + HEAD_WEAR * 0.12 + gen01 * 0.06;
    if (smearAmt > 0.005) {
        const float b = 0.55;
        float smear = (c.r + b * nm1.r + b * b * nm2.r + b * b * b * nm3.r + b * b * b * b * nm4.r)
                    / 2.1103813;
        c.r = mix(c.r, smear, smearAmt);
    }

    const float bc = 0.60;
    vec2 cTail = (c.gb + bc * nm1.gb + bc * bc * nm2.gb + bc * bc * bc * nm3.gb
                  + bc * bc * bc * bc * nm4.gb) / 2.3056;
    vec2 chroma = mix(c.gb, cTail, clamp(0.22 + gen01 * 0.22 + TAPE_SPEED * 0.12, 0.0, 0.60));

    return vec4(c.r, chroma, c.a);
}


//!HOOK MAIN
//!BIND VHS3
//!WIDTH 640 128 STANDARD * +
//!HEIGHT 480 96 STANDARD * +
//!DESC VHS pass 4: vertical blur + aperture, chroma vertical blend, Y/C->RGB, analogue levels

#define TEXEL VHS3_pt
#define TAPE_SPEED (float(RECORDING_MODE) * 0.5)

vec3 c2rgb(vec3 c) {
#if STANDARD == PAL
    return mat3(1.0,      1.0,      1.0,
                0.0,     -0.39465,  2.03211,
                1.13983, -0.58060,  0.0) * c;
#else
    return mat3(1.0,    1.0,     1.0,
                0.9563, -0.2721, -1.1070,
                0.6210, -0.6474,  1.7046) * c;
#endif
}

float h21(vec2 p) {
    uvec2 q = floatBitsToUint(p + vec2(131.0, 1031.0));
    uint n = (q.x * 1597334677u) ^ (q.y * 3812015801u);
    n = (n ^ (n >> 16)) * 2246822519u;
    n = (n ^ (n >> 13)) * 3266489917u;
    n = n ^ (n >> 16);
    return float(n) * (1.0 / 4294967296.0);
}
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = h21(i),                b = h21(i + vec2(1.0, 0.0)),
          c = h21(i + vec2(0.0, 1.0)), d = h21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec4 hook() {
    vec2 uv = VHS3_pos;
    float gen01 = clamp((GENERATION - 1.0) / 4.0, 0.0, 1.0);
    float t = float(frame) * SPEED;

    float oSig = 0.30 + HEAD_WEAR * 0.18 + gen01 * 0.12 + TAPE_SPEED * 0.18;
    float inv2s2 = 1.0 / (2.0 * oSig * oSig);
    float w1 = exp(-inv2s2), w2 = exp(-4.0 * inv2s2);
    vec3 nUp = VHS3_tex(uv + vec2(0.0,  TEXEL.y)).rgb;
    vec3 nDn = VHS3_tex(uv + vec2(0.0, -TEXEL.y)).rgb;
    vec3 c = (VHS3_tex(uv).rgb + (nUp + nDn) * w1
              + (VHS3_tex(uv + vec2(0.0, 2.0 * TEXEL.y)).rgb + VHS3_tex(uv + vec2(0.0, -2.0 * TEXEL.y)).rgb) * w2)
             / (1.0 + 2.0 * w1 + 2.0 * w2);

    float vblur = 0.18 + HEAD_WEAR * 0.16 + HEAD_ALIGNMENT * 0.10 + TAPE_SPEED * 0.12;
    c.x = c.x * (1.0 - 2.0 * vblur) + (nUp.r + nDn.r) * vblur;

    float cvbAmt = clamp(TAPE_SPEED * 0.35 + HEAD_WEAR * 0.20 + HEAD_ALIGNMENT * 0.15, 0.0, 0.55);
    c.yz = mix(c.yz, nDn.yz, cvbAmt);
    float boost = 1.40 - TAPE_AGE * 0.18 - gen01 * 0.10 - TAPE_SPEED * 0.05;
    c.yz *= boost / (1.0 + max(0.0, length(c.yz) * boost - 0.92) * 0.22);

    vec3 rgb = clamp(c2rgb(c), 0.0, 1.0);

    float topLoss = 0.04 + gen01 * 0.05 + TAPE_SPEED * 0.03;
#if STANDARD == PAL
    float blackLift = TAPE_AGE * 0.05 + gen01 * 0.02 + TAPE_SPEED * 0.02;
    rgb = rgb * (1.0 - topLoss) + blackLift;
    rgb -= rgb * rgb * (0.08 + gen01 * 0.06);
#else
    float blackLift = 0.04 + TAPE_AGE * 0.05 + gen01 * 0.02 + TAPE_SPEED * 0.02;
    rgb = rgb * (1.0 - topLoss) + blackLift * vec3(1.03, 1.0, 0.94);
    rgb -= rgb * rgb * (0.08 + gen01 * 0.06);
    rgb *= vec3(1.01, 1.0, 0.97);
#endif
    rgb += (vnoise(uv * vec2(300.0, 220.0) + t * 1.7) - 0.5) * (0.005 + TAPE_WEAR * 0.009 + TAPE_AGE * 0.005);

    return vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
