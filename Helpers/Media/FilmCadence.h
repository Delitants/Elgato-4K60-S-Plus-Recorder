#pragma once
#include <array>
#include <deque>
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstdint>
// Recover the two picture-change phases in each five-frame progressive 3:2 cycle.
// Static/noisy scenes keep the last confident phase instead of guessing from FPS.
class FilmCadence {
 std::array<std::deque<double>,5> history;
 int phase=0;
public:
 std::array<int,2> observe(const std::array<double,5>& differences){
  std::array<double,5> median;
  median.fill(NAN);
  for(int i=0;i<5;i++){
   auto &h=history[i];if(std::isfinite(differences[i]))h.push_back(differences[i]);if(h.size()>6)h.pop_front();
   if(!h.empty()){std::vector<double> values(h.begin(),h.end());std::sort(values.begin(),values.end());median[i]=values[values.size()/2];}
  }
  auto detect=[](const std::array<double,5>& values){
   double best=0;int candidate=-1;
   for(int p=0;p<5;p++){
    int q=(p+2)%5;double low=0,high=INFINITY;
    for(int i=0;i<5;i++)if(std::isfinite(values[i])){
     if(i==p||i==q)high=std::min(high,values[i]);else low=std::max(low,values[i]);
    }
    // The first carrier has no predecessor: its difference is unknown, not zero.
    if(std::isfinite(high) && high>std::max(0.15,low*4) && high/(low+0.05)>best){candidate=p;best=high/(low+0.05);}
   }
   return candidate;
  };
  // Clear current-cycle evidence must not wait behind a history of static frames.
  int candidate=detect(differences);
  // A scene starts with an extra change at the block boundary. The two clear
  // interior transitions still identify its new phase; omit only the partial
  // leading picture instead of losing a complete one in the next cycle.
  if(candidate<0){auto interior=differences;interior[0]=NAN;candidate=detect(interior);}
  if(candidate<0)candidate=detect(median);
  if(candidate>=0)phase=candidate;
  else {
   // Motion can begin with just one change inside the first cycle. Keep both
   // available pictures; there is not enough evidence to change the saved phase.
   for(int p=1;p<5;p++){
    double low=0;for(int i=0;i<5;i++)if(i!=p && std::isfinite(differences[i]))low=std::max(low,differences[i]);
    if(differences[p]>std::max(0.15,low*4))return {0,p};
   }
  }
  std::array<int,2> indices={phase,(phase+2)%5};std::sort(indices.begin(),indices.end());return indices;
 }
};
// Follow the device clock without inheriting its alternating sub-frame jitter.
// A requested 24 vs actual 23.976 must never accumulate A/V drift: each cycle
// gently corrects its anchor against the device PTS. No pictures are invented.
class FilmTimeline {
 double anchor=NAN;
public:
 int64_t cycle(int64_t devicePTS,double picturePeriod){
  if(!std::isfinite(anchor))anchor=double(devicePTS);
  else {anchor+=2*picturePeriod;anchor+=(double(devicePTS)-anchor)/8;}
  return int64_t(std::llround(anchor));
 }
};
