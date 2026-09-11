import Foundation
import FoldCore
@main struct Replay {
 static func main() throws {
    var old=0.0,new=LidMotion(),rows=[[String:Double]]()
    for i in 0...600 {
        let t=Double(i)/120
        let truth=90+6*t,raw=floor(truth)
        let oldTarget=FoldDynamics.progress(angle:raw,clearAngle:110)
        old=i==0 ? oldTarget : FoldDynamics.smooth(old,toward:oldTarget,dt:1/120)
        let angle=new.update(angle:raw,at:t)
        let value=FoldDynamics.progress(angle:angle,clearAngle:110)
        rows.append(["time":t,"raw":raw,"continuous":angle,"before":old,"after":value])
    }
    let data=try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys])
    print(String(data:data,encoding:.utf8)!)
 }
}
