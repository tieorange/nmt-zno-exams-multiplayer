const NAMES = [
  'Веселий Кит', 'Сонячна Жаба', 'Хоробрий Гусак', 'Мудра Сова', 'Швидкий Заєць',
  'Лінивий Ведмідь', 'Бойовий Орел', 'Тихий Кіт', 'Гучний Ворон', 'Добрий Вовк',
  'Смілива Лисиця', 'Сильний Тигр', 'Грайливий Дельфін', 'Чесний Олень', 'Дотепний Пінгвін',
  'Яскравий Папуга', 'Розумна Мавпа', 'Уважна Черепаха', 'Дружній Їжак', 'Чарівний Лось',
  'Кмітливий Бобер', 'Спритний Борсук', 'Задерикуватий Козел', 'Ніжний Лебідь', 'Гордий Лев',
  'Сміливий Сокіл', 'Зворушливий Кролик', 'Незворушний Буйвол', 'Щасливий Дятел', 'Тямущий Рак',
  "Активний Хом'як", 'Бадьорий Качур', 'Стрімкий Леопард', 'Непосидючий Горобець', 'Хитрий Осел',
  'Наполегливий Бик', 'Ласкавий Єнот', 'Загадковий Осьминіг', 'Безстрашний Шакал', 'Ввічливий Кенгуру',
  'Мрійливий Фламінго', 'Відважний Крокодил', 'Спокійний Бегемот', 'Жвавий Горила', 'Привітний Пелікан',
  'Неприборканий Ягуар', 'Допитливий Суслик', 'Терплячий Жираф', 'Чудовий Носоріг', 'Лагідний Зубр',
];

const COLORS = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F'];

const usedNamesInRoom = new Map<string, Set<string>>();

export function assignName(roomCode: string): { name: string; color: string } {
  if (!usedNamesInRoom.has(roomCode)) usedNamesInRoom.set(roomCode, new Set());
  const used = usedNamesInRoom.get(roomCode)!;
  const available = NAMES.filter((n) => !used.has(n));
  const name = available.length > 0
    ? available[Math.floor(Math.random() * available.length)]
    : `Гравець ${used.size + 1}`;
  const colorIndex = used.size % COLORS.length; // capture BEFORE adding name
  used.add(name);
  const color = COLORS[colorIndex];
  return { name, color };
}

export function clearRoom(roomCode: string): void {
  usedNamesInRoom.delete(roomCode);
}
