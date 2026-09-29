#include "../Helpers/Media/FilmCadence.h"
#include <cassert>
#include <iostream>
int main(){
 for(int phase=0;phase<5;phase++){
  FilmCadence cadence;int previous=-1;
  for(int cycle=0;cycle<30;cycle++){
   std::array<double,5> differences{};std::array<int,5> pictures{};
   for(int i=0;i<5;i++){
    int tick=cycle*5+i;pictures[i]=(tick+phase)*2/5;
    differences[i]=tick==0?NAN:double(pictures[i]-(tick-1+phase)*2/5);
   }
   auto selected=cadence.observe(differences);
   for(int index:selected){if(previous>=0)assert(pictures[index]==previous+1);previous=pictures[index];}
  }
 }
 // Static openings and scene edits must not postpone acquiring moving cadence.
 for(int phase=0;phase<5;phase++){
  FilmCadence cadence;int previousSource=0,previousMoving=-1;
  for(int cycle=0;cycle<40;cycle++){
   std::array<double,5> differences{};std::array<int,5> pictures{};
   for(int i=0;i<5;i++){
    int tick=cycle*5+i;pictures[i]=tick<30?0:(tick-30+phase)*2/5+1;
    differences[i]=tick==0?NAN:std::abs(pictures[i]-previousSource);previousSource=pictures[i];
   }
   for(int index:cadence.observe(differences))if(pictures[index]>0){
    if(previousMoving>=0 && pictures[index]!=previousMoving+1){std::cerr<<"phase "<<phase<<" cycle "<<cycle<<" previous "<<previousMoving<<" next "<<pictures[index]<<"\n";assert(false);}previousMoving=pictures[index];
   }
  }
 }
 // An hour of carrier time including timestamp jitter and crossed 24/23.976
 // choices must stay synchronized. Independent output clocks used to drift 3.6 s.
 for(double carrier:{60000.0/1001,60.0})for(double output:{24000.0/1001,24.0}){
  FilmTimeline timeline;int64_t last=-1;
  for(int cycle=0;cycle<43200;cycle++){
   double ideal=1e6+cycle*5e6/carrier;
   int64_t device=llround(ideal+(cycle%2?900:-900));
   int64_t pts=timeline.cycle(device,1e6/output);
   assert(pts>last);assert(std::abs(pts-ideal)<2000);last=pts;
  }
 }
 std::cout<<"PASS film cadence startup: five phases; one-hour device-clock discipline: four rate pairs\n";
}
