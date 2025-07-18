//
//  CalorieSummaryView.swift
//  WatchPlate Watch App
//
//  Created by Omar Sabeha on 6/12/25.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10){
//                    Text("MyFitPlate")
//                        .font(.headline)
//                        .foregroundColor(Color(red: 232/255, green: 240/255, blue: 197/255))
//                        .padding(.top)
                    HStack(spacing: 15) {
                        NavigationLink(destination: NutritionSummaryView()){
                            VStack{
                                Image(systemName: "fork.knife.circle")
                                    .resizable()
                                    .frame(width: 25, height: 25)
                                    .padding(.bottom)
                                Text("Nutrition")
                                    .font(.system(size: 12))
//
//                                Text("summary")
//                                    .font(.system(size: 12))
                            }
                                .foregroundColor(Color.white)
                                .padding()
                                .frame(width: 80, height: 80)
                                .background(Color(red: 40/255, green: 41/255, blue: 40/255))
                                    .cornerRadius(25)
                            
                                
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(red: 29/255, green: 33/255, blue: 30/255))
                        
                        NavigationLink(destination: WaterBottleView()){
                            VStack{
                                Image(systemName: "drop")
                                    .resizable()
                                    .frame(width: 15, height: 25)
                                    .padding(.bottom)
                                Text("Water Log")
                                    .font(.system(size: 12))
                            }
                                .foregroundColor(Color.white)
                                .padding(.vertical,15)
                                .frame(width: 80, height: 80)
                                .background(Color(red: 40/255, green: 41/255, blue: 40/255))
                                .cornerRadius(25)
                        }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(red: 29/255, green: 33/255, blue: 30/255))
                        
                        
                    }
                    
                    HStack(spacing: 15)  {
                        NavigationLink(destination: WeightTracker()){
                            VStack{
                                Image(systemName: "chart.xyaxis.line")
                                    .resizable()
                                    .frame(width: 25, height: 25)
                                    .padding(.bottom)
                                Text("Weight")
                                    .font(.system(size: 12))
//                                Text("Tracker")
//                                    .font(.system(size: 12))
                            }
                                .foregroundColor(Color.white)
//                                .padding(.vertical,15)
                                .frame(width: 80, height: 80)
                                .background(Color(red: 40/255, green: 41/255, blue: 40/255))
                                .cornerRadius(25)
                        }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(red: 29/255, green: 33/255, blue: 30/255))
                        
                        
                        NavigationLink(destination: AIBot()){
                            VStack{
                                Image(systemName: "message")
                                    .resizable()
                                    .frame(width: 25, height: 25)
                                    .padding(.bottom)
                                Text("Recipe Bot")
                                    .font(.system(size: 12))
                            }
                                .foregroundColor(Color.white)
//                                .padding(.vertical,15)
                                .frame(width: 80, height: 80)
                                .background(Color(red: 40/255, green: 41/255, blue: 40/255))
                                .cornerRadius(25)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(red: 29/255, green: 33/255, blue: 30/255))
                    }
                    
                    HStack(spacing: 15)  {
                        NavigationLink(destination: AIBot()){
                            VStack{
                                Image(systemName: "person.circle")
                                    .resizable()
                                    .frame(width: 25, height: 25)
                                    .padding(.bottom)
                                Text("Profile")
                                    .font(.system(size: 12))
                            }
                                .foregroundColor(Color.white)
//                                .padding(.vertical,15)
                                .frame(width: 80, height: 80)
                                .background(Color(red: 40/255, green: 41/255, blue: 40/255))
                                .cornerRadius(25)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(red: 29/255, green: 33/255, blue: 30/255))
                    }
                }
//                .padding(.top)
//
                .navigationTitle("") // hide default title
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("MyFitPlate")
                            .font(.headline)
                            .foregroundColor(Color(red: 164/255, green: 164/255, blue: 164/255))
                    }
                }

                
                
            }
        }
    }
}



        
#Preview {
    HomeView()
}
