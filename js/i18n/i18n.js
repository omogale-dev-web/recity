import en from './en.js'; import mr from './mr.js';
const dictionaries={en,mr};
const productionCopy={
  en:{demoAccount:'Your RECITY ID is created securely for this device.',locationUnavailable:'Location is optional. Allow access when submitting to attach your current coordinates.',municipalDemo:'Municipal preview'},
  mr:{demoAccount:'या उपकरणासाठी तुमचा रेसिटी आयडी सुरक्षितपणे तयार केला जातो.',locationUnavailable:'ठिकाण ऐच्छिक आहे. तक्रार नोंदवताना तुमचे सध्याचे निर्देशांक जोडण्यासाठी परवानगी द्या.',municipalDemo:'महानगरपालिका पूर्वावलोकन'}
};
export const t=(key)=>{const active=localStorage.getItem('recity-language')||'en';return productionCopy[active]?.[key]||dictionaries[active][key]||en[key]||key;};
export const lang=()=>localStorage.getItem('recity-language')||'en';
export const setLanguage=(value)=>{localStorage.setItem('recity-language',value);document.documentElement.lang=value;};
