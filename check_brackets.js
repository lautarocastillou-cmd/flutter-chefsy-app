const fs = require('fs');
let code = fs.readFileSync('C:\\\\Users\\\\usuario\\\\Desktop\\\\chefsy\\\\app_cadete_flutter\\\\lib\\\\screens\\\\portal_screen.dart', 'utf8');
let lines = code.split('\n');

let stack = [];
let inBlockComment = false;

for(let i=0; i<lines.length; i++) {
  let line = lines[i];
  let inString = false;
  let stringChar = '';
  
  for(let j=0; j<line.length; j++) {
    if (inBlockComment) {
      if (line[j] === '*' && line[j+1] === '/') {
        inBlockComment = false;
        j++;
      }
      continue;
    }
    
    if (inString) {
      if (line[j] === '\\\\') {
        j++; // skip escaped char
        continue;
      }
      if (line[j] === stringChar) {
        inString = false;
      }
      continue;
    }
    
    if (line[j] === '/' && line[j+1] === '*') {
      inBlockComment = true;
      j++;
      continue;
    }
    
    if (line[j] === '/' && line[j+1] === '/') {
      break; // line comment
    }
    
    if (line[j] === '\\'' || line[j] === '"') {
      inString = true;
      stringChar = line[j];
      continue;
    }
    
    if (line[j] === '[') { stack.push({line: i+1, type: '['}); }
    if (line[j] === '{') { stack.push({line: i+1, type: '{'}); }
    if (line[j] === '(') { stack.push({line: i+1, type: '('}); }
    
    if (line[j] === ']') {
      if(stack.length && stack[stack.length-1].type === '[') stack.pop();
      else console.log('UNMATCHED ] AT LINE', i+1);
    }
    if (line[j] === '}') {
      if(stack.length && stack[stack.length-1].type === '{') stack.pop();
      else console.log('UNMATCHED } AT LINE', i+1);
    }
    if (line[j] === ')') {
      if(stack.length && stack[stack.length-1].type === '(') stack.pop();
      else console.log('UNMATCHED ) AT LINE', i+1);
    }
  }
}
console.log('Unclosed brackets at EOF:', stack);
