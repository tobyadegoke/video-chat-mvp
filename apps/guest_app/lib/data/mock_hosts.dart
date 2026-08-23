class Host {
  final String id;
  final String name;
  final String imageUrl;
  final bool isOnline;
  final bool isLive;
  final String category;

  const Host({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.isOnline,
    required this.isLive,
    required this.category,
  });
}

const mockHosts = [
  Host(
    id: '1',
    name: 'Maya',
    imageUrl: 'https://i.pravatar.cc/300?img=47',
    isOnline: true,
    isLive: false,
    category: 'Just Chatting',
  ),
  Host(
    id: '2',
    name: 'Sophia',
    imageUrl: 'https://i.pravatar.cc/300?img=32',
    isOnline: true,
    isLive: true,
    category: 'Music & Chat',
  ),
  Host(
    id: '3',
    name: 'Amara',
    imageUrl: 'https://i.pravatar.cc/300?img=44',
    isOnline: true,
    isLive: true,
    category: 'Lifestyle',
  ),
  Host(
    id: '4',
    name: 'Zara',
    imageUrl: 'https://i.pravatar.cc/300?img=49',
    isOnline: false,
    isLive: false,
    category: 'Entertainment',
  ),
  Host(
    id: '5',
    name: 'Nia',
    imageUrl: 'https://i.pravatar.cc/300?img=45',
    isOnline: true,
    isLive: false,
    category: 'Gaming',
  ),
];