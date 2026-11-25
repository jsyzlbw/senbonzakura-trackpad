import Foundation
import CoreGraphics
import CoreText

private let W = 1920.0, H = 1080.0, BEAT = 0.387097
private func C(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
private let PAPER = C(0.93, 0.86, 0.72), INK = C(0.08, 0.07, 0.09), RED = C(0.84, 0.22, 0.15)
private let DRED = C(0.50, 0.10, 0.10), PINK = C(0.96, 0.66, 0.70), INDIGO = C(0.13, 0.17, 0.30)

private func hsh(_ i: Int, _ k: Int) -> Double {
    var x = UInt64(bitPattern: Int64(i &* 7919 &+ k &* 104729 &+ 17))
    x ^= x >> 33; x &*= 0xff51afd7ed558ccd; x ^= x >> 33; x &*= 0xc4ceb9fe1a85ec53; x ^= x >> 33
    return Double(x % 10000) / 10000
}
private func fmod2(_ a: Double, _ m: Double) -> Double { let r = a.truncatingRemainder(dividingBy: m); return r < 0 ? r + m : r }
private func ss(_ a: Double, _ b: Double, _ x: Double) -> Double { let u = max(0, min(1, (x - a) / (b - a))); return u * u * (3 - 2 * u) }

private func txt(_ c: CGContext, _ s: String, _ x: Double, _ y: Double, _ size: Double, _ col: CGColor) {
    let font = CTFontCreateWithName("Hiragino Mincho ProN W6" as CFString, size, nil)
    let attr = [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: col] as [NSAttributedString.Key: Any]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attr))
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    c.saveGState(); c.translateBy(x: x - w / 2, y: y + size * 0.35); c.scaleBy(x: 1, y: -1)
    c.textPosition = .zero; CTLineDraw(line, c); c.restoreGState()
}

private func fill(_ c: CGContext, _ col: CGColor) { c.setFillColor(col); c.fill(CGRect(x: -400, y: -400, width: W + 800, height: H + 800)) }

private func sun(_ c: CGContext, _ x: Double, _ y: Double, _ r: Double, _ col: CGColor) {
    c.setFillColor(col); c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

private func mountains(_ c: CGContext, _ base: Double, _ amp: Double, _ col: CGColor, _ seed: Double, _ off: Double) {
    c.setFillColor(col); c.beginPath(); c.move(to: CGPoint(x: -400, y: H + 400))
    var x = -400.0
    while x <= W + 400 {
        let p = (x + off) * 0.003
        let y = base - amp * (0.55 + 0.3 * sin(p + seed) + 0.25 * abs(sin(p * 2.3 + seed * 2)) - 0.1 * sin(p * 5.1))
        c.addLine(to: CGPoint(x: x, y: y)); x += 40
    }
    c.addLine(to: CGPoint(x: W + 400, y: H + 400)); c.fillPath()
}

private func clouds(_ c: CGContext, _ y: Double, _ off: Double, _ col: CGColor) {
    c.setFillColor(col)
    for i in 0..<6 {
        let w = 260 + hsh(i, 3) * 320, x = fmod2(hsh(i, 4) * 2600 + off, 2600) - 400
        let yy = y + hsh(i, 5) * 160
        c.addPath(CGPath(roundedRect: CGRect(x: x, y: yy, width: w, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
        c.addPath(CGPath(roundedRect: CGRect(x: x + w * 0.2, y: yy - 26, width: w * 0.5, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil))
    }
    c.fillPath()
}

private func torii(_ c: CGContext, _ cx: Double, _ by: Double, _ s: Double, _ col: CGColor) {
    c.setFillColor(col)
    let pw = s * 0.08, sp = s * 0.36
    c.fill(CGRect(x: cx - sp - pw / 2, y: by - s, width: pw, height: s))
    c.fill(CGRect(x: cx + sp - pw / 2, y: by - s, width: pw, height: s))
    c.fill(CGRect(x: cx - sp * 1.25, y: by - s * 0.78, width: sp * 2.5, height: s * 0.07))
    c.beginPath()
    c.move(to: CGPoint(x: cx - sp * 1.6, y: by - s * 1.06))
    c.addQuadCurve(to: CGPoint(x: cx + sp * 1.6, y: by - s * 1.06), control: CGPoint(x: cx, y: by - s * 0.9))
    c.addLine(to: CGPoint(x: cx + sp * 1.45, y: by - s * 0.93))
    c.addQuadCurve(to: CGPoint(x: cx - sp * 1.45, y: by - s * 0.93), control: CGPoint(x: cx, y: by - s * 0.82))
    c.fillPath()
    c.fill(CGRect(x: cx - pw * 0.4, y: by - s * 0.95, width: pw * 0.8, height: s * 0.18))
}

private func branch(_ c: CGContext, _ x: Double, _ y: Double, _ len: Double, _ a: Double, _ d: Int, _ t: Double, _ id: Int, _ bl: CGColor, _ bloom: Double) {
    let sway = 0.03 * sin(t * 1.3 + Double(id)) * Double(6 - d)
    let ex = x + cos(a + sway) * len, ey = y + sin(a + sway) * len
    c.setLineWidth(max(3, Double(d) * 6)); c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: ex, y: ey)); c.strokePath()
    if d == 0 {
        let r = (22 + hsh(id, 1) * 26) * bloom
        c.setFillColor(bl); c.fillEllipse(in: CGRect(x: ex - r, y: ey - r, width: 2 * r, height: 2 * r)); return
    }
    let sp = 0.35 + hsh(id, 2) * 0.25
    branch(c, ex, ey, len * 0.74, a - sp, d - 1, t, id * 2 + 1, bl, bloom)
    branch(c, ex, ey, len * 0.70, a + sp, d - 1, t, id * 2 + 2, bl, bloom)
}

private func tree(_ c: CGContext, _ x: Double, _ y: Double, _ s: Double, _ t: Double, _ col: CGColor, _ bl: CGColor, _ bloom: Double, _ lean: Double = -0.15) {
    c.setStrokeColor(col); c.setLineCap(.round)
    branch(c, x, y, s, -Double.pi / 2 + lean, 6, t, 1, bl, bloom)
}

private func pagoda(_ c: CGContext, _ cx: Double, _ by: Double, _ s: Double, _ col: CGColor) {
    c.setFillColor(col)
    for i in 0..<5 {
        let f = 1 - Double(i) * 0.13, y = by - Double(i) * s * 0.19, w = s * 0.5 * f
        c.fill(CGRect(x: cx - w * 0.45, y: y - s * 0.12, width: w * 0.9, height: s * 0.12))
        c.beginPath(); c.move(to: CGPoint(x: cx - w, y: y - s * 0.1))
        c.addQuadCurve(to: CGPoint(x: cx + w, y: y - s * 0.1), control: CGPoint(x: cx, y: y - s * 0.22))
        c.addLine(to: CGPoint(x: cx, y: y - s * 0.19)); c.closePath(); c.fillPath()
    }
    c.fill(CGRect(x: cx - s * 0.012, y: by - s * 1.2, width: s * 0.024, height: s * 0.3))
}

private func bird(_ c: CGContext, _ x: Double, _ y: Double, _ s: Double, _ ph: Double, _ col: CGColor) {
    let f = sin(ph) * s * 0.6
    c.setFillColor(col); c.beginPath(); c.move(to: CGPoint(x: x - s, y: y - f))
    c.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - s * 0.5, y: y - f * 0.2 - s * 0.25))
    c.addQuadCurve(to: CGPoint(x: x + s, y: y - f), control: CGPoint(x: x + s * 0.5, y: y - f * 0.2 - s * 0.25))
    c.addQuadCurve(to: CGPoint(x: x, y: y + s * 0.22), control: CGPoint(x: x + s * 0.4, y: y + s * 0.1))
    c.addQuadCurve(to: CGPoint(x: x - s, y: y - f), control: CGPoint(x: x - s * 0.4, y: y + s * 0.1))
    c.fillPath()
}

private func waves(_ c: CGContext, _ t: Double, _ y: Double, _ amp: Double, _ col: CGColor, _ foam: CGColor, _ sp: Double) {
    c.setFillColor(col); c.beginPath(); c.move(to: CGPoint(x: -400, y: H + 400))
    var x = -400.0
    while x <= W + 400 { c.addLine(to: CGPoint(x: x, y: y + amp * sin(x * 0.006 + t * sp) + amp * 0.4 * sin(x * 0.017 - t * sp * 1.7))); x += 30 }
    c.addLine(to: CGPoint(x: W + 400, y: H + 400)); c.fillPath()
    c.setFillColor(foam)
    for i in 0..<14 {
        let fx = fmod2(Double(i) * 170 - t * sp * 60, W + 400) - 200
        let fy = y + amp * sin(fx * 0.006 + t * sp) + amp * 0.4 * sin(fx * 0.017 - t * sp * 1.7)
        c.fillEllipse(in: CGRect(x: fx - 16, y: fy - 12, width: 32, height: 22))
    }
}

private func petals(_ c: CGContext, _ t: Double, _ n: Int, _ wind: Double, _ col: CGColor) {
    c.setFillColor(col)
    for i in 0..<n {
        let sz = 12 + hsh(i, 1) * 18, sp = 0.6 + hsh(i, 2)
        let x = fmod2(hsh(i, 3) * (W + 300) + t * wind * sp * 120, W + 300) - 150
        let y = fmod2(hsh(i, 4) * (H + 200) + t * sp * 90 + 30 * sin(t + Double(i)), H + 200) - 100
        c.saveGState(); c.translateBy(x: x, y: y); c.rotate(by: t * (hsh(i, 5) - 0.5) * 4 + Double(i))
        c.scaleBy(x: 1, y: 0.45 + 0.4 * abs(sin(t * 2 + Double(i))))
        c.fillEllipse(in: CGRect(x: -sz, y: -sz * 0.6, width: sz * 2, height: sz * 1.2)); c.restoreGState()
    }
}

private func frame(_ c: CGContext, _ col: CGColor, _ w: Double) {
    c.setStrokeColor(col); c.setLineWidth(w); c.stroke(CGRect(x: 40, y: 40, width: W - 80, height: H - 80))
}

func drawMV(_ c: CGContext, _ t: Double) {
    let pulse = exp(-fmod2(t / BEAT, 1) * 4)
    let cuts = [0, 30.968, 55.742, 80.516, 105.290, 130.065, 154.839, 185.807, 222.968, 251.0]
    var k = 0; while k < 8 && t >= cuts[k + 1] { k += 1 }
    let u = t - cuts[k], len = cuts[k + 1] - cuts[k], p = u / len
    c.saveGState()
    switch k {
    case 0, 7: // 朱日・鳥居・山：开场与回归
        fill(c, PAPER)
        let z = k == 0 ? 1 + 0.08 * p : 1.15 - 0.1 * p
        c.translateBy(x: W / 2, y: H / 2); c.scaleBy(x: z, y: z); c.translateBy(x: -W / 2, y: -H / 2)
        sun(c, W / 2, 470, 300 + 10 * pulse, RED)
        clouds(c, 300, u * 30, C(0.93, 0.86, 0.72, 0.9))
        mountains(c, 860, 300, C(0.55, 0.42, 0.38), 1, u * 10)
        mountains(c, 960, 220, DRED, 3, u * 25)
        torii(c, W / 2, 1010, 620, INK)
        mountains(c, 1100, 160, INK, 5, u * 50)
        petals(c, t, k == 0 ? Int(20 + 60 * p) : 140 + Int(120 * p), 1.2, PINK)
        if k == 0 || p < 0.12 {
            let a = k == 0 ? 1 - ss(24, 30, t) : 1 - ss(0.06, 0.12, p)
            c.setFillColor(C(0.93, 0.86, 0.72, 0.85 * a)); c.fill(CGRect(x: 610, y: 70, width: 700, height: 210))
            txt(c, "千本桜", W / 2, 170, 150, C(0.08, 0.07, 0.09, a))
            txt(c, "SENBONZAKURA · piano", W / 2, 250, 30, C(0.50, 0.10, 0.10, a))
        }
    case 1, 4: // 樱树：主歌（4为夜色变奏）
        let night = k == 4
        fill(c, night ? INDIGO : PAPER)
        c.translateBy(x: -120 * p, y: 0)
        sun(c, 1500, 300, 170, night ? PAPER : RED)
        mountains(c, 900, 200, night ? C(0.2, 0.24, 0.38) : C(0.75, 0.6, 0.5), 2, 0)
        tree(c, 700, 1080, 230, t, INK, night ? PINK : RED, ss(0, 0.6, p) * 0.8 + 0.2)
        mountains(c, 1120, 120, INK, 7, 0)
        petals(c, t, Int(40 + 140 * p), 0.8, night ? PINK : RED)
    case 2, 5: // 鸟居回廊推进：副歌（5为反色变奏）
        let inv = k == 5
        fill(c, inv ? INK : RED)
        let sp = u * 2.2 + (inv ? 0.5 : 0)
        for i in stride(from: 7, through: 0, by: -1) {
            let d = Double(i) - fmod2(sp, 1)
            if d < 0.15 { continue }
            let s = 900 / d, a = min(1, 1.6 / d)
            torii(c, W / 2 + sin(u * 0.5) * 60 / d, H / 2 + s * 0.45, s, inv ? C(0.84, 0.22, 0.15, a) : C(0.08, 0.07, 0.09, a))
        }
        c.setStrokeColor(inv ? C(0.96, 0.66, 0.7, 0.35) : C(0.93, 0.86, 0.72, 0.35)); c.setLineWidth(6)
        for i in 0..<16 {
            let ang = Double(i) * 0.39 + u * 0.2, r0 = 300 + 400 * fmod2(u * 1.5 + hsh(i, 1), 1)
            c.move(to: CGPoint(x: W / 2 + cos(ang) * r0, y: H / 2 + sin(ang) * r0))
            c.addLine(to: CGPoint(x: W / 2 + cos(ang) * (r0 + 220), y: H / 2 + sin(ang) * (r0 + 220)))
        }
        c.strokePath()
        petals(c, t * 1.6, 220, 2.5, inv ? PINK : PAPER)
        frame(c, inv ? RED : INK, 10 + 10 * pulse)
    case 3: // 五重塔与鹤群：过门
        fill(c, PAPER)
        clouds(c, 180, -u * 40, C(0.84, 0.22, 0.15, 0.35))
        sun(c, 420, 330, 150, RED)
        mountains(c, 880, 240, C(0.6, 0.5, 0.45), 4, u * 15)
        pagoda(c, 1350 - 80 * p, 990, 720, INK)
        mountains(c, 1080, 140, INK, 6, u * 40)
        for i in 0..<9 {
            let bx = fmod2(Double(i) * 240 + u * (180 + Double(i % 3) * 40), W + 400) - 200
            bird(c, bx, 260 + hsh(i, 2) * 260 + 20 * sin(u + Double(i)), 46 + hsh(i, 3) * 30, u * 6 + Double(i), INK)
        }
        petals(c, t, 120, 1.5, RED)
    case 6: // 浪与疾风：器乐桥段（快奏加速）
        fill(c, INK)
        let fast = ss(6.2, 7.5, u), sp = 1.2 + 1.6 * fast
        c.translateBy(x: W / 2, y: H / 2); c.rotate(by: -0.06 * sin(u * 0.8)); c.translateBy(x: -W / 2, y: -H / 2)
        sun(c, 1400, 360, 230 + 20 * pulse, RED)
        waves(c, u, 640, 70, INDIGO, PAPER, sp)
        waves(c, u + 2, 780, 90, C(0.2, 0.26, 0.42), PAPER, sp * 1.2)
        for i in 0..<5 { bird(c, fmod2(Double(i) * 420 + u * 300 * sp, W + 400) - 200, 200 + Double(i) * 50, 60, u * 9 + Double(i), PAPER) }
        waves(c, u + 4, 930, 110, PAPER, RED, sp * 1.4)
        petals(c, t * sp, 200, 3, PINK)
        frame(c, RED, 8 + 14 * pulse * fast)
    default: // 尾奏：一枝樱与标题收束
        fill(c, PAPER)
        sun(c, W / 2, 420, 260 * (1 - 0.3 * p), RED)
        mountains(c, 980, 200, C(0.7, 0.58, 0.5), 8, -u * 8)
        tree(c, 1600, 1100, 210, t * 0.5, INK, PINK, 1 - 0.5 * p, -0.6)
        mountains(c, 1100, 110, INK, 9, -u * 15)
        petals(c, t * (1 - 0.5 * p), Int(260 * (1 - p)) + 20, 0.6, RED)
        let a = ss(0.55, 0.75, p)
        txt(c, "千本桜", W / 2, 430, 160, C(0.93, 0.86, 0.72, a))
    }
    c.restoreGState()
    // 段落交界的墨色擦除转场
    let dEdge = min(abs(t - cuts[k]), abs(cuts[k + 1] - t))
    if k > 0 && dEdge < 0.35 { c.setFillColor(C(0.08, 0.07, 0.09, 0.8 * (1 - dEdge / 0.35))); c.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
    if t > 248.5 { c.setFillColor(C(0.93, 0.86, 0.72, ss(248.5, 250.68, t))); c.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
}