import 'dart:io';

void main() {
  var file = File('lib/screens/portal_screen.dart');
  var code = file.readAsStringSync();
  
  // Strip block comments
  code = code.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  // Strip line comments
  code = code.replaceAll(RegExp(r'//.*'), '');
  // Strip strings
  code = code.replaceAll(RegExp(r'"(\\.|[^"\\])*"'), '');
  code = code.replaceAll(RegExp(r"'(\\.|[^'\\])*'"), '');
  
  var lines = code.split('\n');
  int count = 0;
  for (int i = 0; i < lines.length; i++) {
    var line = lines[i];
    for (int j = 0; j < line.length; j++) {
      if (line[j] == '[') count++;
      if (line[j] == ']') count--;
    }
  }
  print('Bracket Balance: $count');
  
  int parenCount = 0;
  for (int i = 0; i < lines.length; i++) {
    var line = lines[i];
    for (int j = 0; j < line.length; j++) {
      if (line[j] == '(') parenCount++;
      if (line[j] == ')') parenCount--;
    }
  }
  print('Paren Balance: $parenCount');
}
