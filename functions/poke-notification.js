// Device preference controls interface copy; group names are always preserved.
function pokeNotification(poke, languageCode) {
  if (languageCode === 'en') {
    return {
      title: 'Someone is looking for you',
      body: poke.pokeCount < 5
        ? `Your teammates in “${poke.groupName}” poked you ${poke.pokeCount} ${poke.pokeCount === 1 ? 'time' : 'times'}!`
        : poke.pokeCount < 10 ? 'Your teammates keep poking you‼️ Come back! 🫨' : 'Your team needs you. Time to check in! 😤',
    };
  }
  return {
    title: '有人在找你',
    body: poke.pokeCount < 5
      ? `你被${poke.groupName}的隊員戳了${poke.pokeCount} 下！`
      : poke.pokeCount < 10 ? '你的組員一直在戳你‼️快回來啦🫨' : '檢舉雷包，人人有責😤',
  };
}
module.exports = { pokeNotification };
