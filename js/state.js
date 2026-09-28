import {users} from './mock/users.js'; import {complaints} from './mock/complaints.js'; import {storage} from './integrations/storage.js';
export const state={screen:'welcome',role:'citizen',user:users[0],analysis:null,selectedItem:null,selectedComplaint:null,photo:false,photoSrc:null,photoName:null,tools:[],time:'15',reports:storage.get('recity-reports',complaints.map(x=>({...x}))),theme:localStorage.getItem('recity-theme')||'light'};
// TODO: MOVE REWARD CALCULATION SERVER-SIDE LATER
export const persist=()=>storage.set('recity-reports',state.reports);
export const setTheme=value=>{state.theme=value;localStorage.setItem('recity-theme',value);document.documentElement.dataset.theme=value;};
