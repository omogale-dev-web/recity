export const wasteItems={
 bottle:{key:'plasticBottle',material:'pet',condition:'cleanBottle',reusable:true,recyclable:true,hazard:'none',confidence:94,emoji:'🧴',ideas:['planter','drip','storage']},
 cardboard:{key:'cardboardBox',material:'cardboard',condition:'cleanBottle',reusable:true,recyclable:true,hazard:'none',confidence:91,emoji:'📦'},
 can:{key:'aluminumCan',material:'aluminium',condition:'used',reusable:true,recyclable:true,hazard:'none',confidence:92,emoji:'🥫'},
 glass:{key:'brokenGlass',material:'glass',condition:'damaged',reusable:false,recyclable:true,hazard:'medium',confidence:96,emoji:'🔎'},
 battery:{key:'battery',material:'batteryMaterial',condition:'used',reusable:false,recyclable:true,hazard:'high',confidence:98,emoji:'🔋'}
};
export const defaultAnalysis={items:[wasteItems.bottle,wasteItems.cardboard,wasteItems.can,wasteItems.glass],summary:'Plastic + household waste',hazard:'low'};
export const hazardousAnalysis={items:[wasteItems.battery],summary:'Hazardous electronic waste',hazard:'high'};
