class PerfilUsuario {
  String nome;
  String cognome;
  String descricao;
  String motivos;

  PerfilUsuario({
    this.nome = "",
    this.cognome = "",
    this.descricao = "",
    this.motivos = "",
  });

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'cognome': cognome,
      'descricao': descricao,
      'motivos': motivos,
    };
  }

  factory PerfilUsuario.fromMap(Map<String, dynamic> map) {
    return PerfilUsuario(
      nome: map['nome'] ?? '',
      cognome: map['cognome'] ?? '',
      descricao: map['descricao'] ?? '',
      motivos: map['motivos'] ?? '',
    );
  }
}
