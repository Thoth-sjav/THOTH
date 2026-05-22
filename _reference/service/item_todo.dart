class ItemTodo {
  String texto;
  String dataHora;
  bool concluido;

  ItemTodo({
    required this.texto,
    required this.dataHora,
    this.concluido = false,
  });
}
