import Foundation
@main struct AudioRingTests {
 static func main() {
  let ring=PCMPlaybackRing(capacity:16,prime:4)
  ring.setEnabled(true)
  func pcm(_ values:[Int16])->Data {var d=Data();for v in values {var x=v.littleEndian;withUnsafeBytes(of:&x){d.append(contentsOf:$0);d.append(contentsOf:$0)}};return d}
  let l=UnsafeMutablePointer<Float>.allocate(capacity:20),r=UnsafeMutablePointer<Float>.allocate(capacity:20)
  defer{l.deallocate();r.deallocate()}
  ring.append(pcm([1000,2000]));assert(ring.read(left:l,right:r,frames:2)==0);assert(l[0]==0)
  ring.append(pcm([3000,4000]));assert(ring.read(left:l,right:r,frames:3)==3);assert(l[0]==Float(1000)/32768 && r[2]==Float(3000)/32768)
  assert(ring.read(left:l,right:r,frames:3)==1);assert(l[0]==Float(4000)/32768 && l[1]==0)
  ring.append(pcm([5000,6000]));assert(ring.read(left:l,right:r,frames:2)==0)
  ring.append(pcm([7000,8000]));assert(ring.read(left:l,right:r,frames:4)==4)
  ring.append(pcm(Array(repeating:1000,count:16)));ring.append(pcm(Array(repeating:2000,count:4)))
  assert(ring.read(left:l,right:r,frames:4)==4 && l[0]==Float(2000)/32768)
  ring.setEnabled(false);assert(ring.read(left:l,right:r,frames:4)==0)
  print("PASS audio ring: exact PCM, stereo, priming, starvation silence, recovery, bounded overflow, mute")
 }
}
