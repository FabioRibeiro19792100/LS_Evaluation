/* Configuração das etapas conforme o Regulamento Learning Sectors 2026.
   As telas leem esta estrutura; mudanças de regulamento ficam centralizadas aqui. */
window.LS_RODADAS = [
  {
    id: 1, slug: "inscricoes", nome: "Inscrições", titulo: "Seleção das inscrições",
    entrega: "Narrativa de ideação", corte: 19,
    orientacao: "Avalie a narrativa de ideação enviada pela equipe.",
    criterios: [
      {k:"edi", nome:"EDI (Equidade, Diversidade e Inclusão)", curto:"EDI", peso:30, desc:"Como a proposta promove a inclusão e a equidade dentro da comunidade escolar. Ponto positivo: soluções que ampliam o acesso e atendem a diferentes perfis de usuários.", ex:["Considera as necessidades de diferentes grupos da comunidade escolar","Incentiva a participação equitativa nas equipes","Amplia a acessibilidade e evita reforçar estereótipos ou práticas discriminatórias","Valoriza a equidade e a diversidade entre os públicos atendidos pela solução"]},
      {k:"originalidade", nome:"Originalidade e Criatividade", curto:"Originalidade", peso:20, desc:"A capacidade de propor soluções inovadoras e a aplicação criativa dos conceitos STEM. Ponto positivo: uso de técnicas ou tecnologias pouco exploradas no contexto escolar.", ex:["Abordagem nova ou criativa para o problema identificado","Inovação na aplicação dos conceitos STEM","Ideias que diferem de práticas já comuns na comunidade escolar","Potencial de inspirar novas abordagens em outros contextos educacionais"]},
      {k:"qualidade", nome:"Qualidade da Proposta", curto:"Qualidade", peso:20, desc:"A clareza, a consistência e a demonstração da solução apresentada, bem como a capacidade do(a) professor(a)-líder de indicar o impacto da proposta em sala de aula. Ponto positivo: proposta bem estruturada, com problema, solução e impacto pedagógico claramente articulados.", ex:["A narrativa de ideação explicita com clareza o problema, sua relevância, a solução e o impacto em sala de aula","O(a) professor(a)-líder descreve mudanças observadas ou esperadas na aprendizagem, no engajamento, na participação ou na dinâmica da turma","A solução é clara e prática para o público-alvo","Há equilíbrio entre simplicidade e eficiência na concepção da solução"]},
      {k:"viabilidade", nome:"Viabilidade", curto:"Viabilidade", peso:15, desc:"O realismo e a consistência do caminho proposto para a implementação da solução. Ponto positivo: planejamento claro e alinhado à realidade da comunidade escolar.", ex:["Pode ser implementada com os recursos financeiros, materiais e humanos disponíveis","Solução sustentável no longo prazo","Plano de ação bem estruturado","Considera limitações práticas, como infraestrutura e tempo disponível"]},
      {k:"impacto", nome:"Impacto Social", curto:"Impacto", peso:15, desc:"A contribuição para a educação, a transformação social e a sustentabilidade da comunidade escolar. Ponto positivo: benefícios claros e duradouros para a comunidade escolar.", ex:["Aborda um problema significativo e beneficia a comunidade escolar","Atende a uma necessidade real e relevante","Potencial de melhorar significativamente o ambiente educacional","Pode ser replicada ou adaptada para outros contextos"]}
    ]
  },
  {
    id: 2, slug: "planos", nome: "Planos de ação", titulo: "Seleção dos planos de ação",
    entrega: "Business Model Canvas", corte: 10,
    orientacao: "Avalie o plano de ação apresentado no formato Business Model Canvas, aplicando os mesmos critérios e pesos da seleção das inscrições.",
    criterios: null
  },
  {
    id: 3, slug: "banca", nome: "Banca", titulo: "Avaliação da banca final",
    entrega: "Pitch e arguição", corte: 3,
    orientacao: "Avalie o pitch de até 3 minutos e a arguição de até 5 minutos realizada pela banca.",
    criterios: [
      {k:"viabilidade", nome:"Viabilidade", curto:"Viabilidade", peso:25, desc:"Consistência do caminho de implementação apresentado.", ex:[]},
      {k:"inovacao", nome:"Inovação", curto:"Inovação", peso:25, desc:"Originalidade da solução e da abordagem apresentada no pitch.", ex:[]},
      {k:"arguicao", nome:"Arguição", curto:"Arguição", peso:25, desc:"Clareza e consistência da argumentação da equipe diante da banca.", ex:[]},
      {k:"impacto", nome:"Impacto", curto:"Impacto", peso:25, desc:"Potencial de transformação da solução para a comunidade escolar.", ex:[]}
    ]
  }
];
window.LS_RODADAS[1].criterios = window.LS_RODADAS[0].criterios.map(c => ({...c}));
window.LS_RODADA = id => window.LS_RODADAS.find(r => r.id === Number(id)) || window.LS_RODADAS[0];
