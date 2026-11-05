import Foundation

/// Inbyggda övningslåtar (fria från upphovsrätt), skrivna i ABC-notation.
public enum ExampleSongs {

    public struct Example: Sendable {
        public var id: String
        public var abc: String
    }

    public static let all: [Example] = [
        Example(id: "example.scale", abc: """
        X:1
        T:C-durskala (uppvärmning)
        M:4/4
        L:1/4
        Q:1/4=80
        K:C
        V:1 name="Höger hand"
        V:2 name="Vänster hand" clef=bass
        [V:1] C D E F | G A B c | c B A G | F E D C |]
        [V:2] C, D, E, F, | G, A, B, C | C B, A, G, | F, E, D, C, |]
        """),

        Example(id: "example.twinkle", abc: """
        X:2
        T:Blinka lilla stjärna
        M:4/4
        L:1/4
        Q:1/4=90
        K:C
        V:1 name="Höger hand"
        V:2 name="Vänster hand" clef=bass
        [V:1] C C G G | A A G2 | F F E E | D D C2 |
        [V:2] C,4 | F,2 C,2 | F,2 C,2 | G,,2 C,2 |
        [V:1] G G F F | E E D2 | G G F F | E E D2 |
        [V:2] C,2 F,2 | C,2 G,,2 | C,2 F,2 | C,2 G,,2 |
        [V:1] C C G G | A A G2 | F F E E | D D C2 |]
        [V:2] C,4 | F,2 C,2 | F,2 C,2 | G,,2 C,2 |]
        """),

        Example(id: "example.mary", abc: """
        X:3
        T:Mary Had a Little Lamb
        M:4/4
        L:1/4
        Q:1/4=100
        K:C
        E D C D | E E E2 | D D D2 | E G G2 |
        E D C D | E E E E | D D E D | C4 |]
        """),

        Example(id: "example.ode", abc: """
        X:4
        T:Glädjens sång (Beethoven)
        M:4/4
        L:1/4
        Q:1/4=100
        K:C
        V:1 name="Höger hand"
        V:2 name="Vänster hand" clef=bass
        [V:1] E E F G | G F E D | C C D E | E3/2 D/2 D2 |
        [V:2] C,4 | G,,4 | C,4 | C,2 G,,2 |
        [V:1] E E F G | G F E D | C C D E | D3/2 C/2 C2 |
        [V:2] C,4 | G,,4 | C,4 | G,,2 C,2 |
        [V:1] D D E C | D E/F/ E C | D E/F/ E D | C D G,2 |
        [V:2] G,,4 | G,,2 C,2 | G,,2 C,2 | C,2 G,,2 |
        [V:1] E E F G | G F E D | C C D E | D3/2 C/2 C2 |]
        [V:2] C,4 | G,,4 | C,4 | G,,2 C,2 |]
        """),

        Example(id: "example.jingle", abc: """
        X:5
        T:Jingle Bells (refräng)
        M:4/4
        L:1/4
        Q:1/4=110
        K:C
        E E E2 | E E E2 | E G C3/2 D/2 | E4 |
        F F F3/2 F/2 | F E E E/2 E/2 | E D D E | D2 G2 |
        E E E2 | E E E2 | E G C3/2 D/2 | E4 |
        F F F F | F E E E/2 E/2 | G G F D | C4 |]
        """),

        Example(id: "example.elise", abc: """
        X:6
        T:Für Elise (början)
        M:3/8
        L:1/16
        Q:1/8=110
        K:Am
        V:1 name="Höger hand"
        V:2 name="Vänster hand" clef=bass
        [V:1] e^d | e^de B=dc | A2 z CEA | B2 z E^GB | c2 z E e^d |
        [V:2] z2 | z6 | A,,E,A, z3 | E,,E,^G, z3 | A,,E,A, z3 |
        [V:1] e^de B=dc | A2 z CEA | B2 z EcB | A4 z2 |]
        [V:2] z6 | A,,E,A, z3 | E,,E,^G, z3 | A,,E,A, z3 |]
        """),
    ]
}
