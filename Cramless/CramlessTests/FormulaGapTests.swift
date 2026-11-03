import XCTest
@testable import Cramless

/// Typeset formulas that vanished from a PDF's text layer, found from the prose they leave holes in. The pages are the
/// text layer of Wikipedia's "Chain rule" as a PDF (CC BY-SA), whose formulas are pictures: "…the chain rule is expressed
/// as" / "and" / "for indicating at which points…". Twelve of the fourteen pages are such pages; the last two are references,
/// which never had a formula. Prose in French, German and Spanish, lists, tables, slides and code must never be flagged: a flag
/// offers to spend scans. Then the better read that fixes a flagged page is merged into the page's lines (`PageLayout.merged`).
final class FormulaGapTests: XCTestCase {

    /// Page 1 of the PDF (printed 1).
    static let first: [String] = [
        #"Chain rule"#,
        #"In calculus, the chain rule is a formula that expresses the derivative of the composition of two differentiable functions z"#,
        #"and y in terms of the derivatives of z and y. More precisely, if is the composition such that for"#,
        #"every x, then the chain rule is, in Lagrange's notation,"#,
        #"or, equivalently,"#,
        #"The chain rule may also be expressed in Leibniz's notation. If a variable z depends on the variable y, which itself depends"#,
        #"on the variable x (that is, y and z are dependent variables), then z depends on x as well, via the intermediate variable y. In"#,
        #"this case, the chain rule is expressed as"#,
        #"and"#,
        #"for indicating at which points the derivatives have to be evaluated."#,
        #"In integration, the counterpart to the chain rule is the substitution rule."#,
        #"Intuitive explanation"#,
        #"Intuitively, the chain rule states that knowing the instantaneous rate of change of z relative to y and that of y relative to x"#,
        #"allows one to calculate the instantaneous rate of change of z relative to x as the product of the two rates of change."#,
        #"As put by George F. Simmons: "If a car travels twice as fast as a bicycle and the bicycle is four times as fast as a walking"#,
        #"man, then the car travels 2 × 4 = 8 times as fast as the man."[1][2]"#,
        #"The relationship between this example and the chain rule is as follows. Let z, y and x be the (variable) positions of the car,"#,
        #"the bicycle, and the walking man, respectively. The rate of change of relative positions of the car and the bicycle is"#,
        #"Similarly, So, the rate of change of the relative positions of the car and the walking man is"#,
    ]

    /// Page 3 of the PDF (printed 3).
    static let composites: [String] = [
        #"Carrying the same reasoning further, given n functions with the composite function ,"#,
        #"if each function is differentiable at its immediate input, then the composite function is also differentiable by the repeated"#,
        #"application of the chain rule, where the derivative is (in Leibniz's notation):"#,
        #"Applications"#,
        #"Composites of more than two functions"#,
        #"The chain rule can be applied to composites of more"#,
        #"than two functions. To take the derivative of a composite"#,
        #"of more than two functions, notice that the composite of"#,
        #"f, g, and h (in that order) is the composite of f with"#,
        #"g ∘ h. The chain rule states that to compute the"#,
        #"derivative of f ∘ g ∘ h, it is sufficient to compute the"#,
        #"derivative of f and the derivative of g ∘ h. The"#,
        #"derivative of f can be calculated directly, and the"#,
        #"derivative of g ∘ h can be calculated by applying the"#,
        #"chain rule again.[6]"#,
        #"For concreteness, consider the function"#,
        #"This can be decomposed as the composite of three"#,
        #"functions:"#,
        #"So that ."#,
        #"Their derivatives are:"#,
        #"The chain rule in case of composites of more than two functions"#,
        #"The chain rule states that the derivative of their composite at the point x = a is:"#,
    ]

    /// Page 4 of the PDF (printed 4).
    static let leibniz: [String] = [
        #"In Leibniz's notation, this is:"#,
        #"or for short,"#,
        #"The derivative function is therefore:"#,
        #"Another way of computing this derivative is to view the composite function f ∘ g ∘ h as the composite of f ∘ g and h."#,
        #"Applying the chain rule in this manner would yield:"#,
        #"This is the same as what was computed above. This should be expected because (f ∘ g) ∘ h = f ∘ (g ∘ h)."#,
        #"Sometimes, it is necessary to differentiate an arbitrarily long composition of the form case, define"#,
        #". In this"#,
        #"where and when . Then the chain rule takes the form"#,
        #"or, in the Lagrange notation,"#,
        #"Quotient rule"#,
    ]

    /// Page 7 of the PDF (printed 7).
    static let proof: [String] = [
        #"zero. To work around this, introduce a function as follows:"#,
        #"We will show that the difference quotient for f ∘ g is always equal to:"#,
        #"Whenever g(x) is not equal to g(a), this is clear because the factors of g(x) − g(a) cancel. When g(x) equals g(a), then"#,
        #"the difference quotient for f ∘ g is zero because f(g(x)) equals f(g(a)), and the above product is zero because it equals"#,
        #"f′(g(a)) times zero. So the above product is always equal to the difference quotient, and to show that the derivative of f ∘ g"#,
        #"at a exists and to determine its value, we need only show that the limit as x goes to a of the above product exists and"#,
        #"determine its value."#,
        #"To do this, recall that the limit of a product exists if the limits of its factors exist. When this happens, the limit of the product"#,
        #"of these two factors will equal the product of the limits of the factors. The two factors are Q(g(x)) and"#,
        #"(g(x) − g(a)) / (x − a). The latter is the difference quotient for g at a, and because g is differentiable at a by assumption,"#,
        #"its limit as x tends to a exists and equals g′(a)."#,
        #"As for Q(g(x)), notice that Q is defined wherever f is. Furthermore, f is differentiable at g(a) by assumption, so Q is"#,
        #"continuous at g(a), by definition of the derivative. The function g is continuous at a because it is differentiable at a, and"#,
        #"therefore Q ∘ g is continuous at a. So its limit as x goes to a exists and equals Q(g(a)), which is f′(g(a))."#,
        #"This shows that the limits of both factors exist and that they equal f′(g(a)) and g′(a), respectively. Therefore, the derivative"#,
        #"of f ∘ g at a exists and equals f′(g(a))g′(a)."#,
        #"Second proof"#,
        #"Another way of proving the chain rule is to measure the error in the linear approximation determined by the derivative. This"#,
        #"proof has the advantage that it generalizes to several variables. It relies on the following equivalent definition of"#,
        #"differentiability at a point: A function g is differentiable at a if there exists a real number g′(a) and a function ε(h) that tends"#,
        #"to zero as h tends to zero, and furthermore"#,
        #"Here the left-hand side represents the true difference between the value of g at a and at a + h, whereas the right-hand side"#,
        #"represents the approximation determined by the derivative plus an error term."#,
        #"In the situation of the chain rule, such a function ε exists because g is assumed to be differentiable at a. Again by"#,
        #"assumption, a similar function also exists for f at g(a). Calling this function η, we have"#,
        #"The above definition imposes no constraints on η(0), even though it is assumed that η(k) tends to zero as k tends to zero. If"#,
        #"we set η(0) = 0, then η is continuous at 0."#,
    ]

    /// Page 12 of the PDF (printed 12).
    static let multivariable: [String] = [
        #"In the special case where k = 1, so that f is a real-valued function, then this formula simplifies even further:"#,
        #"This can be rewritten as a dot product. Recalling that u = (g1, …, gm), the partial derivative ∂u / ∂xi is also a vector, and"#,
        #"the chain rule says that:"#,
        #"Example"#,
        #"the chain rule."#,
        #"Given u(x, y) = x2 + 2y where x(r, t) = r sin(t) and y(r,t) = sin2(t), determine the value of ∂u / ∂r and ∂u / ∂t using"#,
        #"and"#,
        #"Higher derivatives of multivariable functions"#,
        #"Faà di Bruno's formula for higher-order derivatives of single-variable functions generalizes to the multivariable case. If"#,
        #"y = f(u) is a function of u = g(x) as above, then the second derivative of f ∘ g is:"#,
        #"Further generalizations"#,
        #"All extensions of calculus have a chain rule. In most of these, the formula remains the same, though the meaning of that"#,
        #"formula may be vastly different."#,
        #"One generalization is to manifolds. In this situation, the chain rule represents the fact that the derivative of f ∘ g is the"#,
        #"composite of the derivative of f and the derivative of g. This theorem is an immediate consequence of the higher"#,
        #"dimensional chain rule given above, and it has exactly the same formula."#,
    ]

    /// Page 13 of the PDF (printed 13).
    static let references: [String] = [
        #"The chain rule is also valid for Fréchet derivatives in Banach spaces. The same formula holds as before.[10] This case and"#,
        #"the previous one admit a simultaneous generalization to Banach manifolds."#,
        #"In differential algebra, the derivative is interpreted as a morphism of modules of Kähler differentials. A ring homomorphism"#,
        #"of commutative rings f : R → S determines a morphism of Kähler differentials Df : ΩR → ΩS which sends an element"#,
        #"dr to d(f(r)), the exterior differential of f(r). The formula D(f ∘ g) = Df ∘ Dg holds in this context as well."#,
        #"The common feature of these examples is that they are expressions of the idea that the derivative is part of a functor. A"#,
        #"functor is an operation on spaces and functions between them. It associates to each space a new space and to each function"#,
        #"between two spaces a new function between the corresponding new spaces. In each of the above cases, the functor sends"#,
        #"each space to its tangent bundle and it sends each function to its derivative. For example, in the manifold case, the"#,
        #"derivative sends a Cr-manifold to a Cr−1-manifold (its tangent bundle) and a Cr-function to its total derivative. There is"#,
        #"one requirement for this to be a functor, namely that the derivative of a composite must be the composite of the derivatives."#,
        #"This is exactly the formula D(f ∘ g) = Df ∘ Dg."#,
        #"There are also chain rules in stochastic calculus. One of these, Itō's lemma, expresses the composite of an Itō process (or"#,
        #"more generally a semimartingale) dXt with a twice-differentiable function f. In Itō's lemma, the derivative of the composite"#,
        #"function depends not only on dXt and the derivative of f but also on the second derivative of f. The dependence on the"#,
        #"second derivative is a consequence of the non-zero quadratic variation of the stochastic process, which broadly speaking"#,
        #"means that the process can move up and down in a very rough way. This variant of the chain rule is not an example of a"#,
        #"functor because the two functions being composed are of different types."#,
        #"See also"#,
        #"Automatic differentiation – Numerical calculations carrying along derivatives − a computational method that"#,
        #"makes heavy use of the chain rule to compute exact numerical derivatives."#,
        #"Differentiation rules – Rules for computing derivatives of functions"#,
        #"Integration by substitution – Technique in integral evaluation"#,
        #"Leibniz integral rule – Differentiation under the integral sign formula"#,
        #"Product rule – Formula for the derivative of a product"#,
        #"Quotient rule – Formula for the derivative of a ratio of functions"#,
        #"Triple product rule – Relation between relative derivatives of three variables"#,
        #"References"#,
        #"1. George F. Simmons, Calculus with Analytic Geometry (1985), p. 93."#,
        #"2. Simmons, George F. (1996). Calculus with Analytic Geometry. McGraw-Hill. p. 115. ISBN 9780070575295."#,
        #"Internet Archive"#,
        #"3. Child, J. M. (1917). "THE MANUSCRIPTS OF LEIBNIZ ON HIS DISCOVERY OF THE DIFFERENTIAL"#,
        #"CALCULUS. PART II (Continued)" (https://www.jstor.org/stable/27900650). The Monist. 27 (3): 411–454."#,
        #"doi:10.5840/monist191727324 (https://doi.org/10.5840%2Fmonist191727324). ISSN 0026-9662 (https://sear"#,
        #"ch.worldcat.org/issn/0026-9662). JSTOR 27900650 (https://www.jstor.org/stable/27900650)."#,
        #"4. Rodríguez, Omar Hernández; López Fernández, Jorge M. (2010). "A Semiotic Reflection on the Didactics of"#,
        #"the Chain Rule" (https://scholarworks.umt.edu/tme/vol7/iss2/10/). The Mathematics Enthusiast. 7 (2): 321–"#,
        #"332. doi:10.54870/1551-3440.1191 (https://doi.org/10.54870%2F1551-3440.1191)."#,
        #"5. Apostol, Tom (1974). Mathematical analysis (2nd ed.). Addison Wesley. Theorem 5.5."#,
        #"6. Landau, L. D., and E. M. Lifshitz. Mechanics. Course of Theoretical Physics, Vol. 1. Pergamon Press, 1960,"#,
        #"§12."#,
        #"7. Goodfellow, Ian; Bengio, Yoshua; Courville, Aaron (2016), Deep learning, MIT, pp=197–217."#,
    ]

    /// Page 2 of the PDF (printed 2).
    static let page2: [String] = [
        #"The rate of change of positions is the ratio of the speeds, and the speed is the derivative of the position with respect to the"#,
        #"time; that is,"#,
        #"or, equivalently,"#,
        #"which is also an application of the chain rule."#,
        #"History"#,
        #"The chain rule seems to have first been used by Gottfried Wilhelm Leibniz. He used it to calculate the derivative of"#,
        #"as the composite of the square root function and the function . He first mentioned it in a 1676"#,
        #"memoir (with a sign error in the calculation).[3] The common notation of the chain rule is due to Leibniz.[4] Guillaume de"#,
        #"l'Hôpital used the chain rule implicitly in his Analyse des infiniment petits. The chain rule does not appear in any of"#,
        #"Leonhard Euler's analysis books, even though they were written over a hundred years after Leibniz's discovery."#,
        #"[4] It is"#,
        #"believed that the first "modern" version of the chain rule appears in Lagrange's 1797 Théorie des fonctions analytiques; it"#,
        #"also appears in Cauchy's 1823 Résumé des Leçons données a L’École Royale Polytechnique sur Le Calcul Infinitesimal."#,
        #"[4]"#,
        #"Statement"#,
        #"The simplest form of the chain rule is for real-valued functions of one real variable. It states that if g is a function that is"#,
        #"differentiable at a point c (i.e. the derivative g′(c) exists) and f is a function that is differentiable at g(c), then the"#,
        #"composite function is differentiable at c, and the derivative is[5]"#,
        #"The rule is sometimes abbreviated as"#,
        #"If y = f(u) and u = g(x), then this abbreviated form is written in Leibniz notation as:"#,
        #"The points where the derivatives are evaluated may also be stated explicitly:"#,
    ]

    /// Page 5 of the PDF (printed 5).
    static let page5: [String] = [
        #"The chain rule can be used to derive some well-known differentiation rules. For example, the quotient rule is a consequence"#,
        #"of the chain rule and the product rule. To see this, write the function f(x)/g(x) as the product f(x) · 1/g(x). First apply the"#,
        #"product rule:"#,
        #"To compute the derivative of 1/g(x), notice that it is the composite of g with the reciprocal function, that is, the function"#,
        #"that sends x to 1/x. The derivative of the reciprocal function is . By applying the chain rule, the last expression"#,
        #"becomes:"#,
        #"which is the usual formula for the quotient rule."#,
        #"Derivatives of inverse functions"#,
        #"Suppose that y = g(x) has an inverse function. Call its inverse function f so that we have x = f(y). There is a formula for"#,
        #"the derivative of f in terms of the derivative of g. To see this, note that f and g satisfy the formula"#,
        #"And because the functions function with value 1, and the derivative of and x are equal, their derivatives must be equal. The derivative of x is the constant"#,
        #"is determined by the chain rule. Therefore, we have that:"#,
        #"To express f'"#,
        #"f'"#,
        #"."#,
        #"as a function of an independent variable y, we substitute for x wherever it appears. Then we can solve for"#,
        #"For example, consider the function g(x) = ex"#,
        #". It has an inverse f(y) = ln y. Because g′(x) = ex"#,
        #", the above formula says"#,
        #"that"#,
    ]

    /// Page 6 of the PDF (printed 6).
    static let page6: [String] = [
        #"This formula is true whenever g is differentiable and its inverse f is also differentiable. This formula can fail when one of"#,
        #"these conditions is not true. For example, consider g(x) = x3"#,
        #". Its inverse is f(y) = y1/3"#,
        #", which is not differentiable at zero."#,
        #"If we attempt to use the above formula to compute the derivative of f at zero, then we must evaluate 1/g′(f(0)). Since"#,
        #"f(0) = 0 and g′(0) = 0, we must evaluate 1/0, which is undefined. Therefore, the formula fails in this case. This is not"#,
        #"surprising because f is not differentiable at zero."#,
        #"Backpropagation"#,
        #"The chain rule forms the basis of the backpropagation algorithm, which is used in gradient descent of neural networks in"#,
        #"deep learning (artificial intelligence).[7]"#,
        #"Higher derivatives"#,
        #"Faà di Bruno's formula generalizes the chain rule to higher derivatives. Assuming that y = f(u) and u = g(x), then the first"#,
        #"few derivatives are:"#,
        #"Proofs"#,
        #"First proof"#,
        #"One proof of the chain rule begins by defining the derivative of the composite function f ∘ g, where we take the limit of the"#,
        #"difference quotient for f ∘ g as x approaches a:"#,
        #"Assume for the moment that of two factors:"#,
        #"does not equal for any near . Then the previous expression is equal to the product"#,
        #"If oscillates near a, then it might happen that no matter how close one gets to a, there is always an even closer x such that"#,
        #"g(x) = g(a). For example, this happens near a = 0 for the continuous function g defined by g(x) = 0 for x = 0 and"#,
        #"g(x) = x2 sin(1/x) otherwise. Whenever this happens, the above expression is undefined because it involves division by"#,
    ]

    /// Page 8 of the PDF (printed 8).
    static let page8: [String] = [
        #"Proving the theorem requires studying the difference f(g(a + h)) − f(g(a)) as h tends to zero. The first step is to substitute"#,
        #"for g(a + h) using the definition of differentiability of g at a:"#,
        #"The next step is to use the definition of differentiability of f at g(a). This requires a term of the form f(g(a) + k) for some k."#,
        #"In the above equation, the correct k varies with h. Set kh = g′(a) h + ε(h) h and the right hand side becomes"#,
        #"f(g(a) + kh) − f(g(a)). Applying the definition of the derivative gives:"#,
        #"To study the behavior of this expression as h tends to zero, expand kh. After regrouping the terms, the right-hand side"#,
        #"becomes:"#,
        #"Because ε(h) and η(kh) tend to zero as h tends to zero, the first two bracketed terms tend to zero as h tends to zero. Applying"#,
        #"the same theorem on products of limits as in the first proof, the third bracketed term also tends zero. Because the above"#,
        #"expression is equal to the difference f(g(a + h)) − f(g(a)), by the definition of the derivative f ∘ g is differentiable at a"#,
        #"and its derivative is f′(g(a)) g′(a)."#,
        #"The role of Q in the first proof is played by η in this proof. They are related by the equation:"#,
        #"The need to define Q at g(a) is analogous to the need to define η at zero."#,
        #"Third proof"#,
        #"the chain rule.[8]"#,
        #"Constantin Carathéodory's alternative definition of the differentiability of a function can be used to give an elegant proof of"#,
        #"Under this definition, a function f is differentiable at a point a if and only if there is a function q, continuous at a and such"#,
        #"that f(x) − f(a) = q(x)(x − a). There is at most one such function, and if f is differentiable at a then f ′(a) = q(a)."#,
        #"Given the assumptions of the chain rule and the fact that differentiable functions and compositions of continuous functions"#,
        #"are continuous, we have that there exist functions q, continuous at g(a), and r, continuous at a, and such that,"#,
        #"and"#,
        #"Therefore,"#,
        #"but the function given by h(x) = q(g(x))r(x) is continuous at a, and we get, for this a"#,
    ]

    /// Page 9 of the PDF (printed 9).
    static let page9: [String] = [
        #"A similar approach works for continuously differentiable (vector-)functions of many variables. This method of factoring"#,
        #"also allows a unified approach to stronger forms of differentiability, when the derivative is required to be Lipschitz"#,
        #"continuous, Hölder continuous, etc. Differentiation itself can be viewed as the polynomial remainder theorem (the little"#,
        #"Bézout theorem, or factor theorem), generalized to an appropriate class of functions."#,
        #"Multivariable case"#,
        #"The full generalization of the chain rule to multi-variable functions (such as is simpler to write in the case of functions of the form"#,
        #") is rather technical. However, it"#,
        #"where , and for each"#,
        #"As this case occurs often in the study of functions of a single variable, it is worth describing it separately."#,
        #"Case of scalar-valued multivariate functions"#,
        #"Let , and for each To write the chain rule for the composition of functions"#,
        #"one needs the partial derivatives of f with respect to its k arguments. The usual notations for partial derivatives involve"#,
        #"names for the arguments of the function. As these arguments are not named in the above formula, it is simpler and clearer to"#,
        #"use D-Notation, and to denote by"#,
        #"the partial derivative of f with respect to its ith argument, and by"#,
        #"the value of this derivative at z."#,
        #"With this notation, the chain rule is"#,
        #"Example: arithmetic operationsIf the function f is addition, that is, if"#,
    ]

    /// Page 10 of the PDF (printed 10).
    static let page10: [String] = [
        #"then and . Thus, the chain rule gives"#,
        #"For multiplication"#,
        #"the partials are and . Thus,"#,
        #"The case of exponentiation"#,
        #"is slightly more complicated, as"#,
        #"and, as"#,
        #"It follows that"#,
        #"General rule: Vector-valued multivariate functions"#,
        #"The simplest way for writing the chain rule in the general case is to use the total derivative, which is a linear transformation"#,
        #"that captures all directional derivatives in a single formula. Consider differentiable functions f : Rm"#,
        #"→ Rk and"#,
        #"g : Rn"#,
        #"→ Rm"#,
        #", and a point a in Rn"#,
        #". Let Da g denote the total derivative of g at a and Dg(a) f denote the total derivative"#,
        #"of f at g(a). These two derivatives are linear transformations Rn"#,
        #"→ Rm and Rm"#,
        #"→ Rk"#,
        #", respectively, so they can be"#,
        #"composed. The chain rule for total derivatives is that their composite is the total derivative of f ∘ g at a:"#,
        #"or for short,"#,
        #"The higher-dimensional chain rule can be proved using a technique similar to the second proof given above.[9]"#,
    ]

    /// Page 11 of the PDF (printed 11).
    static let page11: [String] = [
        #"Because the total derivative is a linear transformation, the functions appearing in the formula can be rewritten as matrices."#,
        #"The matrix corresponding to a total derivative is called a Jacobian matrix, and the composite of two derivatives corresponds"#,
        #"to the product of their Jacobian matrices. From this perspective the chain rule therefore says:"#,
        #"or for short,"#,
        #"That is, the Jacobian of a composite function is the product of the Jacobians of the composed functions (evaluated at the"#,
        #"appropriate points)."#,
        #"The higher-dimensional chain rule is a generalization of the one-dimensional chain rule. If k, m, and n are 1, so that"#,
        #"f : R → R and g : R → R, then the Jacobian matrices of f and g are 1 × 1. Specifically, they are:"#,
        #"The Jacobian of f ∘ g is the product of these 1 × 1 matrices, so it is f′(g(a))⋅g′(a), as expected from the one-dimensional"#,
        #"chain rule. In the language of linear transformations, Da(g) is the function which scales a vector by a factor of g′(a) and"#,
        #"Dg(a)(f) is the function which scales a vector by a factor of f′(g(a)). The chain rule says that the composite of these two"#,
        #"linear transformations is the linear transformation Da(f ∘ g), and therefore it is the function that scales a vector by"#,
        #"f′(g(a))⋅g′(a)."#,
        #"Another way of writing the chain rule is used when f and g are expressed in terms of their components as"#,
        #"y = f(u) = (f1(u), …, fk(u)) and u = g(x) = (g1(x), …, gm(x)). In this case, the above rule for Jacobian matrices is"#,
        #"usually written as:"#,
        #"The chain rule for total derivatives implies a chain rule for partial derivatives. Recall that when the total derivative exists,"#,
        #"the partial derivative in the i-th coordinate direction is found by multiplying the Jacobian matrix by the i-th basis vector. By"#,
        #"doing this to the formula above, we find:"#,
        #"Since the entries of the Jacobian matrix are partial derivatives, we may simplify the above formula to get:"#,
        #"More conceptually, this rule expresses the fact that a change in the xi direction may change all of g1 through gm, and any of"#,
        #"these changes may affect f."#,
    ]

    /// Page 14 of the PDF (printed 14): the last of the references.
    static let page14: [String] = [
        #"8. Kuhn, Stephen (1991). "The Derivative á la Carathéodory". The American Mathematical Monthly. 98 (1): 40–"#,
        #"44. doi:10.2307/2324035 (https://doi.org/10.2307%2F2324035). JSTOR 2324035 (https://www.jstor.org/stabl"#,
        #"e/2324035)."#,
        #"9. Spivak, Michael (1965). Calculus on Manifolds. Boston: Addison-Wesley. pp. 19–20. ISBN 0-8053-9021-9."#,
        #"10. Cheney, Ward (2001). "The Chain Rule and Mean Value Theorems". Analysis for Applied Mathematics. New"#,
        #"York: Springer. pp. 121–125. ISBN 0-387-95279-9."#,
        #"Further reading"#,
        #"Abou-Hayt, Imad; Dahl, Bettina (2025-03-29). "Using a Realistic Context to Motivate and Teach Engineering"#,
        #"Students the Chain Rule" (https://doi.org/10.3390%2Feducsci15040433). Education Sciences. 15 (4): 433."#,
        #"doi:10.3390/educsci15040433 (https://doi.org/10.3390%2Feducsci15040433). ISSN 2227-7102 (https://searc"#,
        #"h.worldcat.org/issn/2227-7102)."#,
        #"External links"#,
        #""Leibniz rule" (https://www.encyclopediaofmath.org/index.php?title=Leibniz_rule), Encyclopedia of"#,
        #"Mathematics, EMS Press, 2001 [1994]"#,
        #"Weisstein, Eric W. "Chain Rule" (https://mathworld.wolfram.com/ChainRule.html). MathWorld."#,
        #"Retrieved from "https://en.wikipedia.org/w/index.php?title=Chain"#,
        #"rule&oldid=1376551040""#,
        #"_"#,
    ]

    /// French puts a space before a colon, a semicolon, a question mark and an exclamation mark: ordinary punctuation.
    static let french: [[String]] = [
        [
            #"La mitose"#,
            #"Définition : la mitose est le processus par lequel une cellule eucaryote se divise en deux cellules filles"#,
            #"génétiquement identiques. Elle permet la croissance des organismes, le remplacement des cellules abîmées"#,
            #"et le maintien des tissus."#,
            #"Étymologie : le mot vient du grec mitos, qui signifie « fil »."#,
            #"Exemple : les cellules de la peau se renouvellent en permanence grâce à la mitose ;"#,
            #"les cellules du foie, elles, se divisent beaucoup plus rarement."#,
            #"Remarque : la mitose ne doit pas être confondue avec la méiose, qui produit les gamètes."#,
            #"Pourquoi la mitose est-elle importante ? Parce qu'elle assure la transmission fidèle du matériel génétique !"#,
            #"Les quatre phases de la mitose sont :"#,
            #"La prophase est la première étape, pendant laquelle les chromosomes se condensent peu à peu."#,
            #"La métaphase aligne les chromosomes au centre de la cellule, sur le plan équatorial."#,
            #"L'anaphase sépare les chromatides sœurs, qui migrent vers les deux pôles opposés de la cellule."#,
            #"La télophase reforme deux noyaux, puis la cellule se divise par cytocinèse."#,
            #"Les trois étapes à retenir :"#,
            #"Chaque chromosome est d'abord copié pendant la phase S de l'interphase du cycle cellulaire."#,
            #"Les chromosomes copiés se séparent ensuite de manière strictement égale entre les deux cellules."#,
            #"Le cytoplasme est enfin partagé, ce qui donne deux cellules filles complètement distinctes."#,
            #"Conclusion : la mitose est un mécanisme précis et très régulé."#,
        ],
        [
            #"Le cycle cellulaire"#,
            #"Le cycle cellulaire comprend deux grandes périodes : l'interphase et la division cellulaire."#,
            #"Pendant l'interphase, la cellule grandit, accomplit ses fonctions et prépare la division ;"#,
            #"elle copie aussi son ADN au cours de la phase S."#,
            #"Voici les points essentiels à connaître :"#,
            #"La phase G1 est une période de croissance pendant laquelle la cellule synthétise des protéines."#,
            #"La phase S correspond à la réplication de l'ADN, qui double la quantité de matériel génétique."#,
            #"La phase G2 prépare la cellule à la mitose et vérifie que la réplication s'est bien déroulée."#,
            #"Définition : un point de contrôle est un mécanisme qui arrête le cycle en cas d'anomalie."#,
            #"Définition : une cellule quiescente est une cellule qui a quitté le cycle sans se diviser."#,
            #"Définition : la cytocinèse est la division du cytoplasme qui suit la mitose."#,
            #"Quelle est la durée moyenne du cycle ? Cela dépend du type de cellule ; en général, environ vingt-quatre heures."#,
            #"Attention : les cellules cancéreuses échappent aux points de contrôle !"#,
            #"Résumé : le cycle cellulaire est une succession d'étapes strictement ordonnées."#,
        ],
    ]

    /// German prose with lists introduced by a colon.
    static let german: [[String]] = [
        [
            #"Die Mitose"#,
            #"Die Mitose ist ein Vorgang der Zellteilung, bei dem aus einer Zelle zwei erbgleiche Tochterzellen entstehen."#,
            #"Sie sorgt für das Wachstum und für die Erneuerung von Geweben."#,
            #"Die Phasen der Mitose:"#,
            #"Die Prophase ist die erste Phase, in der sich die Chromosomen verdichten."#,
            #"In der Metaphase ordnen sich die Chromosomen in der Äquatorialebene an."#,
            #"In der Anaphase werden die Chromatiden zu den Zellpolen gezogen."#,
            #"Die Telophase bildet zwei neue Zellkerne und beendet die Kernteilung."#,
            #"Wichtige Begriffe:"#,
            #"Das Chromosom ist ein Träger der Erbinformation und besteht aus DNA und Proteinen."#,
            #"Die Spindelfasern ziehen die Chromatiden während der Anaphase auseinander."#,
            #"Das Zentromer hält die beiden Chromatiden eines Chromosoms zusammen."#,
            #"Zusammenfassung: Die Mitose verteilt das Erbgut gleichmäßig auf zwei Zellen."#,
        ],
    ]

    /// Spanish prose with lists introduced by a colon.
    static let spanish: [[String]] = [
        [
            #"La mitosis"#,
            #"La mitosis es el proceso por el cual una célula eucariota se divide en dos células hijas idénticas."#,
            #"Las fases de la mitosis son:"#,
            #"La profase es la primera fase, en la que los cromosomas se condensan y se hacen visibles."#,
            #"En la metafase los cromosomas se alinean en el ecuador de la célula antes de separarse."#,
            #"La anafase separa las cromátidas hermanas hacia los polos opuestos de la célula."#,
            #"Los objetivos principales son:"#,
            #"Mantener el número de cromosomas igual en todas las células hijas del organismo."#,
            #"Permitir el crecimiento y la reparación de los tejidos dañados con rapidez."#,
            #"Definición: la citocinesis es la división del citoplasma que sigue a la mitosis."#,
            #"Ejemplo: las células de la piel se renuevan constantemente gracias a este proceso."#,
        ],
    ]

    /// English bullets without a glyph, each introduced by a line that ends in a colon.
    static let englishLists: [[String]] = [
        [
            #"Causes of the war"#,
            #"Historians have long disagreed about why the conflict began, and several explanations compete."#,
            #"The main reasons are:"#,
            #"The alliance system had divided Europe into two armed camps that distrusted each other."#,
            #"Colonial rivalries had raised tension between the great powers for more than a decade."#,
            #"The immediate causes were:"#,
            #"The assassination of the archduke in Sarajevo gave Austria a pretext to act against Serbia."#,
            #"The rapid mobilisation of the armies left very little room for diplomacy to succeed."#,
            #"Key terms to remember:"#,
            #"Militarism meant the growth of armies and the influence of the generals on government policy."#,
            #"Nationalism was the belief that each people should have its own state and its own destiny."#,
        ],
    ]

    /// Tables and truth tables read cell by cell: many one- and two-character lines.
    static let tables: [[String]] = [
        [
            #"Grade distribution"#,
            #"Grade"#,
            #"Count"#,
            #"A"#,
            #"12"#,
            #"B"#,
            #"25"#,
            #"C"#,
            #"31"#,
            #"D"#,
            #"9"#,
            #"F"#,
            #"3"#,
            #"Second term"#,
            #"Grade"#,
            #"Count"#,
            #"A"#,
            #"15"#,
            #"B"#,
            #"22"#,
            #"C"#,
            #"28"#,
            #"D"#,
            #"11"#,
            #"F"#,
            #"4"#,
            #"The table shows that most students scored a B or a C in both terms of the year."#,
        ],
        [
            #"Periodic table excerpt"#,
            #"H"#,
            #"He"#,
            #"Li"#,
            #"Be"#,
            #"B"#,
            #"C"#,
            #"N"#,
            #"O"#,
            #"F"#,
            #"Ne"#,
            #"Na"#,
            #"Mg"#,
            #"Al"#,
            #"Si"#,
            #"P"#,
            #"S"#,
            #"Cl"#,
            #"Ar"#,
            #"The elements are arranged by atomic number, which counts the protons in the nucleus of each atom."#,
        ],
        [
            #"Truth table"#,
            #"p"#,
            #"q"#,
            #"p and q"#,
            #"T"#,
            #"T"#,
            #"T"#,
            #"T"#,
            #"F"#,
            #"F"#,
            #"F"#,
            #"T"#,
            #"F"#,
            #"F"#,
            #"F"#,
            #"F"#,
            #"Conjunction is true only when both of the statements joined by it are true at the same time."#,
        ],
    ]

    /// Slides: short lines all through.
    static let slides: [[String]] = [
        [
            #"Boolean operators"#,
            #"AND"#,
            #"OR"#,
            #"NOT"#,
            #"XOR"#,
            #"NAND"#,
            #"Used to combine conditions in a query"#,
            #"AND returns rows that match both"#,
            #"OR returns rows that match either"#,
            #"NOT excludes rows"#,
            #"Examples on the next slide"#,
            #"Logic gates"#,
            #"AND gate"#,
            #"OR gate"#,
            #"NOT gate"#,
        ],
        [
            #"Agenda"#,
            #"Introduction"#,
            #"Background"#,
            #"Method"#,
            #"Results"#,
            #"Discussion"#,
            #"Conclusions"#,
            #"Questions"#,
            #"Thank you"#,
            #"References"#,
            #"Contact"#,
            #"Appendix"#,
        ],
    ]

    /// Source code.
    static let code: [[String]] = [
        [
            #"def mean(values):"#,
            #"    total = 0"#,
            #"    for v in values:"#,
            #"        total += v"#,
            #"    return total / len(values)"#,
            #""#,
            #"print(mean([1, 2, 3]))"#,
            #"# prints 2.0"#,
            #"if x > 3:"#,
            #"    pass"#,
            #"else:"#,
            #"    print(x)"#,
            #"for i in range(10):"#,
            #"    print(i)"#,
        ],
    ]

    private static let positives: [(String, [String])] = [
        ("page 1", first), ("page 2", page2), ("page 3", composites), ("page 4", leibniz), ("page 5", page5), ("page 6", page6),
        ("page 7", proof), ("page 8", page8), ("page 9", page9), ("page 10", page10), ("page 11", page11), ("page 12", multivariable),
    ]

    private static let negatives: [(String, [String])] = [("page 13", references), ("page 14", page14)]

    func testPagesWhoseFormulasVanishedAreFlagged() {
        XCTAssertEqual(Self.positives.count, 12)
        for (name, lines) in Self.positives {
            XCTAssertTrue(PageLayout.formulasMayBeMissing(page: lines), "\(name): score \(PageLayout.formulaGapScore(page: lines))")
            XCTAssertGreaterThanOrEqual(PageLayout.formulaGapScore(page: lines), PageLayout.formulaGapThreshold)
        }
    }

    func testAPageThatNeverHadFormulasIsNot() {
        for (name, lines) in Self.negatives {
            XCTAssertFalse(PageLayout.formulasMayBeMissing(page: lines), "\(name): score \(PageLayout.formulaGapScore(page: lines))")
        }
    }

    func testProseInFrenchGermanAndSpanishIsNotFlagged() {
        // French puts a space before a colon, a semicolon, a question mark and an exclamation mark, and its pages are full of
        // "Définition : ..." lines; German and Spanish introduce their lists with a colon like English.
        for (index, page) in (Self.french + Self.german + Self.spanish).enumerated() {
            XCTAssertFalse(PageLayout.formulasMayBeMissing(page: page), "page \(index): \(PageLayout.formulaGapEvidence(page: page))")
            XCTAssertLessThan(PageLayout.formulaGapScore(page: page), PageLayout.formulaGapThreshold)
        }
        // Three "Définition :" lines used to be the threshold on their own.
        let definitions = ["Définition : la mitose est le processus par lequel une cellule eucaryote se divise en deux cellules filles.",
                           "Définition : un point de contrôle est un mécanisme qui arrête le cycle en cas d'anomalie du matériel génétique.",
                           "Définition : la cytocinèse est la division du cytoplasme qui suit la mitose dans la plupart des cellules."]
        XCTAssertEqual(PageLayout.formulaGapScore(page: definitions), 0, accuracy: 0.001)
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: definitions + definitions))
    }

    func testListsTablesSlidesAndCodeAreNotFlagged() {
        // Bullets with no glyph: a line that ends in a colon, then capitalised sentences, are a list, not a missing formula.
        for page in Self.englishLists + Self.tables + Self.slides + Self.code {
            XCTAssertFalse(PageLayout.formulasMayBeMissing(page: page), "\(page.first ?? ""): \(PageLayout.formulaGapEvidence(page: page))")
        }
        let twoIntroductions = ["Mitosis occurs in four main phases:", "Prophase is the first phase, in which the chromosomes condense and are visible.",
                                "The cell then divides into two cells, and the cycle starts again in each of the new daughter cells:",
                                "Metaphase aligns the chromosomes along the middle of the cell before they are pulled apart."]
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: twoIntroductions))
        XCTAssertLessThan(PageLayout.formulaGapScore(page: twoIntroductions), PageLayout.formulaGapThreshold)
    }

    func testOrdinaryProseListsAndSlidesAreNot() {
        let prose = [
            "Plaintiff was standing on a platform of defendant's railroad after buying a ticket to go to Rockaway Beach. A train",
            "stopped at the station, bound for another place. Two men ran forward to catch it. One of the men reached the car",
            "without mishap, though the train was already moving. The other man, carrying a package, jumped aboard the car, but",
            "seemed unsteady as if about to fall. A guard on the car, who had held the door open, reached forward to help him in,",
            "and another guard on the platform pushed him from behind. In this act, the package was dislodged, and fell upon the",
            "rails. It was a package of small size, about fifteen inches long, and was covered by a newspaper. In fact it contained",
            "fireworks, but there was nothing in its appearance to give notice of its contents. The fireworks when they fell exploded.",
            "The shock of the explosion threw down some scales at the other end of the platform, many feet away. The scales struck",
        ]
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: prose))
        // A list introduced by a colon is not a formula that went missing.
        let list = [
            "Mitosis occurs in four main phases:", "Prophase", "Metaphase", "Anaphase", "Telophase",
            "Each phase has its own events. In prophase the chromosomes condense and become visible to the microscope.",
            "The cell then divides in two, and the cycle starts again with the growth of each of the new daughter cells.",
        ]
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: list))
        // Slides: short lines all through the document are the document's own shape.
        let slides = (0..<12).map { "Point \($0): a short slide line" }
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: slides, documentMedianLineLength: 30))
        // Too little to judge.
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: ["The chain rule is", "and"]))
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: []))
    }

    func testTheSignsOneByOne() {
        // A line that promises a formula and is followed by a new sentence is only a hint (it is also how a list begins).
        let promise = ["The derivative of the composite function is given by the formula below, which we can state as:",
                       "We will show that the difference quotient is always equal to the product of two simpler factors.",
                       "A second line of ordinary prose that carries on with the argument for a few more words here."]
        var evidence = PageLayout.formulaGapEvidence(page: promise)
        XCTAssertEqual(evidence.traces, 0, accuracy: 0.001)
        XCTAssertEqual(evidence.ambiguous, 1.0, accuracy: 0.001)
        XCTAssertFalse(evidence.flagged)
        // ...unless what follows it is a hole: a bare connector or a stray symbol is a trace.
        let hole = ["The chain rule is expressed as:", "", "and", "", "where the derivative is evaluated at the point a, as before."]
        evidence = PageLayout.formulaGapEvidence(page: hole)
        XCTAssertGreaterThanOrEqual(evidence.traces, 1.5)
        XCTAssertTrue(evidence.flagged)
        XCTAssertEqual(PageLayout.formulaGapScore(page: hole), evidence.total, accuracy: 0.001)
        // A bare connector between two long lines of prose, wherever it sits.
        XCTAssertTrue(PageLayout.isConnectorLine("and"))
        XCTAssertTrue(PageLayout.isConnectorLine("or, equivalently,"))
        XCTAssertTrue(PageLayout.isConnectorLine("or for short,"))
        XCTAssertTrue(PageLayout.isConnectorLine("where"))
        XCTAssertFalse(PageLayout.isConnectorLine("The chain rule"))
        XCTAssertFalse(PageLayout.isConnectorLine("Intuitive explanation of the idea behind it"))
        // ...but two lowercase "and" lines on a slide are not, for want of a long line of prose beside them.
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: ["Union", "and", "Intersection", "and", "Difference", "Venn diagrams on the next slide"]))
        // A space before a comma where a symbol vanished is one small sign.
        let spaced = ["Carrying the same reasoning further, given n functions with the composite function ,",
                      "if each function is differentiable at its immediate input then the composite is too",
                      "and the derivative follows from repeated use of the rule that we have just stated"]
        evidence = PageLayout.formulaGapEvidence(page: spaced)
        XCTAssertEqual(evidence.total, 0.75, accuracy: 0.001)
        XCTAssertFalse(evidence.flagged)
        // A run of one-character lines is the rest of a fraction: a specific trace, and two of them flag the page.
        let fragments = ["Some words before the break in the text that go on a while.", "f'", ".", "Some words after it that go on too."]
        evidence = PageLayout.formulaGapEvidence(page: fragments)
        XCTAssertEqual(evidence.traces, 3.0, accuracy: 0.001)
        XCTAssertTrue(evidence.flagged)
        // Formula words with no symbols on the page, four or more times, are a hint.
        let words = ["The formula for the derivative of a product is taught first.", "Then the equation for the integral follows it.",
                     "A theorem about the derivative closes the section of the notes."]
        evidence = PageLayout.formulaGapEvidence(page: words)
        XCTAssertEqual(evidence.total, 1.0, accuracy: 0.001)
        XCTAssertFalse(evidence.flagged)
        // ...and nothing when the symbols are there.
        let kept = ["The formula for the derivative of a product is (fg)′ = f′g + fg′.", "Then the equation y = f(u) with u = g(x) follows.",
                    "A theorem about the derivative: dy/dx = (dy/du)(du/dx) closes the section."]
        XCTAssertEqual(PageLayout.formulaGapScore(page: kept), 0, accuracy: 0.001)
    }

    func testHintsAloneNeverFlagAPageAndTheThresholdNeedsASpecificTrace() {
        // Total 3.0 or more from hints alone is not enough: a trace (1.5 or more) or four introductions are needed too.
        let hints = PageLayout.FormulaGapEvidence(traces: 0, ambiguous: 4.0, introducers: 3)
        XCTAssertFalse(hints.flagged)
        XCTAssertTrue(PageLayout.FormulaGapEvidence(traces: 0, ambiguous: 4.0, introducers: 4).flagged, "four introductions in one page")
        XCTAssertTrue(PageLayout.FormulaGapEvidence(traces: 1.5, ambiguous: 1.5, introducers: 0).flagged)
        XCTAssertFalse(PageLayout.FormulaGapEvidence(traces: 1.5, ambiguous: 1.4, introducers: 0).flagged, "below the threshold")
        XCTAssertFalse(PageLayout.FormulaGapEvidence(traces: 1.0, ambiguous: 3.0, introducers: 0).flagged, "a trace needs 1.5")
    }

    func testAPageFarShorterThanTheDocumentsIsOneMoreSign() {
        let lines = (0..<10).map { "short line \($0)" }
        XCTAssertEqual(PageLayout.formulaGapScore(page: lines, documentMedianLineLength: 80), 1, accuracy: 0.001)
        XCTAssertEqual(PageLayout.formulaGapScore(page: lines, documentMedianLineLength: 20), 0, accuracy: 0.001)
    }

    func testAWholeDocumentIsJudgedPageByPage() {
        let flags = PageLayout.pagesMissingFormulas([Self.first, Self.references, Self.leibniz, ["One line only"]])
        XCTAssertEqual(flags, [true, false, true, false])
        XCTAssertEqual(PageLayout.pagesMissingFormulas([]), [])
        // All fourteen pages of the PDF, in order, with the document's own line length as the measure.
        let whole = Self.positives.map(\.1) + Self.negatives.map(\.1)
        XCTAssertEqual(PageLayout.pagesMissingFormulas(whole), Array(repeating: true, count: 12) + [false, false])
        // A document in French is not flagged anywhere.
        XCTAssertEqual(PageLayout.pagesMissingFormulas(Self.french + Self.german + Self.spanish), Array(repeating: false, count: 4))
    }

    // MARK: Formulas drawn as outlines

    /// Prose with no sign of a hole in it: a page whose text layer alone gives nothing away.
    private static let intactProse: [String] = [
        "Plaintiff was standing on a platform of defendant's railroad after buying a ticket to go to Rockaway Beach. A train",
        "stopped at the station, bound for another place. Two men ran forward to catch it. One of the men reached the car",
        "without mishap, though the train was already moving. The other man, carrying a package, jumped aboard the car, but",
        "seemed unsteady as if about to fall. A guard on the car, who had held the door open, reached forward to help him in,",
        "and another guard on the platform pushed him from behind. In this act, the package was dislodged, and fell upon the",
        "rails. It was a package of small size, about fifteen inches long, and was covered by a newspaper. In fact it contained",
    ]

    /// The outlines of a formula set on a line: `count` symbols of different sizes (5 to 8 points wide, 7 to 11 tall), nine points apart,
    /// the first at (x, y) (top left of the page).
    private func formulaRow(_ count: Int, x: Double = 100, y: Double = 300) -> [PageLayout.FormulaInk.Piece] {
        (0..<count).map { PageLayout.FormulaInk.Piece(x: x + Double($0) * 9, y: y, width: [5.0, 6, 7, 8][$0 % 4], height: [9.0, 11, 7][$0 % 3]) }
    }

    /// A row of identical marks, `count` of them (the markers of a chart, a column of bullets, a leader of dots).
    private func marks(_ count: Int, x: Double = 100, y: Double = 300, gap: Double = 8) -> [PageLayout.FormulaInk.Piece] {
        (0..<count).map { PageLayout.FormulaInk.Piece(x: x + Double($0) * gap, y: y, width: 5, height: 5) }
    }

    /// The outlines of a small icon: four pieces in a box of ten points, of two sizes.
    private func icon(x: Double, y: Double) -> [PageLayout.FormulaInk.Piece] {
        [(0.0, 0.0, 4.0), (5.0, 0.0, 4.0), (0.0, 5.0, 4.0), (5.0, 5.0, 5.0)].map { PageLayout.FormulaInk.Piece(x: x + $0.0, y: y + $0.1, width: $0.2, height: 4) }
    }

    func testOutlinesThatSitTogetherAreOneFormula() {
        // The symbols of a formula, a gap of a few points between them: one cluster with its box, and the sizes the symbols come in.
        let row = PageLayout.inkClusters(of: formulaRow(8))
        XCTAssertEqual(row.count, 1)
        XCTAssertEqual(row[0].pieces, 8)
        XCTAssertEqual(row[0].width, 71, accuracy: 0.001)
        XCTAssertEqual(row[0].height, 11, accuracy: 0.001)
        XCTAssertEqual(row[0].sizes, 8)
        // A fraction: its numerator, its denominator a few points below it, and its bar, are one.
        let fraction = formulaRow(3) + formulaRow(3, x: 100, y: 313) + [PageLayout.FormulaInk.Piece(x: 100, y: 310, width: 30, height: 2)]
        XCTAssertEqual(PageLayout.inkClusters(of: fraction).map(\.pieces), [7])
        // Symbols a line apart, or a column apart, are separate.
        XCTAssertEqual(PageLayout.inkClusters(of: formulaRow(3) + formulaRow(3, y: 340)).count, 2)
        XCTAssertEqual(PageLayout.inkClusters(of: formulaRow(3) + formulaRow(3, x: 160)).count, 2)
        XCTAssertEqual(PageLayout.inkClusters(of: []), [])
    }

    func testAFormulaDrawnAsOutlinesFlagsAPageWhoseTextGivesNothingAway() {
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: Self.intactProse))
        // A displayed formula (six symbols or more, a row of 24 points or more) is a trace of its own: the page is flagged.
        let displayed = [FormulaInkSummary(displays: 1)]
        XCTAssertTrue(PageLayout.formulasMayBeMissing(page: Self.intactProse, ink: displayed.first))
        let evidence = PageLayout.formulaGapEvidence(page: Self.intactProse, ink: displayed.first)
        XCTAssertEqual(evidence.inkDisplays, 1)
        XCTAssertEqual(evidence.traces, PageLayout.displayInkPoints, accuracy: 0.001)
        XCTAssertTrue(evidence.flagged)
        // From the pieces: the summary of a page with one displayed formula, and the whole document judged with it.
        let summaries = PageLayout.inkSummaries([ink(formulaRow(8)), ink([]), nil])
        XCTAssertEqual(summaries, [FormulaInkSummary(displays: 1, inlines: 0), FormulaInkSummary(), nil])
        let flags = PageLayout.pagesMissingFormulas([Self.intactProse, Self.intactProse, Self.intactProse],
                                                    ink: [ink(formulaRow(8)), ink([]), nil])
        XCTAssertEqual(flags, [true, false, false])
        // Even a page of two lines (a heading and the formula under it) is flagged by what it draws.
        XCTAssertTrue(PageLayout.formulasMayBeMissing(page: ["Entropy", "The definition is"], ink: displayed.first))
    }

    func testIconsBulletsAndShortRowsAreNotAFormula() {
        // Two icons of four pieces in a box of ten points, a row of five symbols, a column of bullets: none is a displayed formula.
        var pieces = icon(x: 100, y: 200) + icon(x: 300, y: 500) + formulaRow(5, y: 400)
        pieces += (0..<8).map { PageLayout.FormulaInk.Piece(x: 30, y: 100 + Double($0) * 20, width: 4, height: 4) }
        let summary = PageLayout.inkSummaries([ink(pieces)])[0]
        XCTAssertEqual(summary, FormulaInkSummary(displays: 0, inlines: 3))
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: Self.intactProse, ink: summary))
        // Three symbols with subscripts alone are not enough either: they need the text to back them.
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: Self.intactProse, ink: FormulaInkSummary(inlines: 5)))
        XCTAssertEqual(PageLayout.formulaGapScore(page: Self.intactProse, ink: FormulaInkSummary(inlines: 5)), 5 * PageLayout.inlineInkPoints, accuracy: 0.001)
    }

    func testTheMarksOfAChartAreNotAFormulaForBeingManyAndNearEachOther() {
        // Ten identical circles in a row (a line chart's markers, a leader of dots) make one cluster of one size: not a formula, however
        // long the row; pairs of identical marks inside a scatter plot are not symbols with subscripts either.
        let row = PageLayout.inkClusters(of: marks(10))
        XCTAssertEqual(row.map(\.pieces), [10])
        XCTAssertEqual(row.map(\.sizes), [1])
        var plot = marks(10)
        for index in 0..<12 { plot += marks(2, x: 30 + Double(index % 4) * 120, y: 400 + Double(index / 4) * 50) }
        XCTAssertEqual(PageLayout.inkSummaries([ink(plot)])[0], FormulaInkSummary())
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: Self.intactProse, ink: PageLayout.inkSummaries([ink(plot)])[0]))
        // The same row with symbols of different sizes is a formula.
        XCTAssertEqual(PageLayout.inkSummaries([ink(formulaRow(10))])[0]?.displays, 1)
    }

    func testSymbolsInsideLinesCountWithAnySignOfAHoleInTheText() {
        // A line that promises a formula and is followed by a new sentence is one point of doubt (see `testTheSignsOneByOne`).
        let promise = ["The derivative of the composite function is given by the formula below, which we can state as:",
                       "We will show that the difference quotient is always equal to the product of two simpler factors.",
                       "A second line of ordinary prose that carries on with the argument for a few more words here."]
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: promise))
        XCTAssertFalse(PageLayout.formulasMayBeMissing(page: promise, ink: FormulaInkSummary(inlines: 3)))
        XCTAssertTrue(PageLayout.formulasMayBeMissing(page: promise, ink: FormulaInkSummary(inlines: 6)))
        // Eight symbols inside the lines of a page are a page of formulas on their own; more add nothing.
        XCTAssertTrue(PageLayout.formulasMayBeMissing(page: Self.intactProse, ink: FormulaInkSummary(inlines: 8)))
        XCTAssertEqual(PageLayout.formulaGapScore(page: Self.intactProse, ink: FormulaInkSummary(inlines: 30)), 8 * PageLayout.inlineInkPoints, accuracy: 0.001)
        XCTAssertEqual(PageLayout.formulaGapScore(page: Self.intactProse, ink: FormulaInkSummary(displays: 5)), 2 * PageLayout.displayInkPoints, accuracy: 0.001)
    }

    func testAMastheadAboveTheFirstSentenceIsNotAFormula() {
        // A site's logo above the first sentence of the first page is eight outlines in a row, and it is not a formula...
        let logo = formulaRow(8, y: 60)
        XCTAssertEqual(PageLayout.inkSummaries([ink(logo)])[0]?.displays, 1)
        XCTAssertEqual(PageLayout.inkSummaries([ink(logo, above: 120)])[0], FormulaInkSummary())
        // ...but the same row under the first sentence is one, and a page with no sentence at all (a cover) has no formula.
        XCTAssertEqual(PageLayout.inkSummaries([ink(formulaRow(8, y: 200), above: 120)])[0]?.displays, 1)
        XCTAssertEqual(PageLayout.inkSummaries([ink(formulaRow(8, y: 200), above: .infinity)])[0], FormulaInkSummary())
    }

    func testWhatIsDrawnInTheSamePlaceOnEveryPageIsNotAFormula() {
        // A logo on each of six slides, a displayed formula on only two of them: the logo repeats (three pages and a quarter of them),
        // the formula does not.
        let logo = formulaRow(8, x: 40, y: 20)
        var pages: [PageLayout.FormulaInk?] = (0..<6).map { _ in ink(logo) }
        pages[1] = ink(logo + formulaRow(9, x: 150, y: 300))
        pages[4] = ink(logo + formulaRow(7, x: 80, y: 420))
        let summaries = PageLayout.inkSummaries(pages)
        XCTAssertEqual(summaries.map { $0?.displays }, [0, 1, 0, 0, 1, 0])
        // On two pages of eight it is not yet a running mark.
        let few: [PageLayout.FormulaInk?] = (0..<8).map { ink($0 < 2 ? logo : []) }
        XCTAssertEqual(PageLayout.inkSummaries(few).map { $0?.displays }, [1, 1, 0, 0, 0, 0, 0, 0])
    }

    func testAMapOrADiagramIsNotAPageOfFormulas() {
        let drawing = (0..<(PageLayout.drawingInkPieces + 1)).map { PageLayout.FormulaInk.Piece(x: Double($0 % 80) * 7, y: Double($0 / 80) * 12, width: 5, height: 8) }
        XCTAssertNil(PageLayout.inkSummaries([ink(drawing)])[0], "nothing is said of it")
        XCTAssertEqual(PageLayout.pagesMissingFormulas([Self.intactProse], ink: [ink(drawing)]), [false])
    }

    func testPagesWhoseDrawingWasNotReadAreJudgedByTheirTextAlone() {
        let whole = Self.positives.map(\.1) + Self.negatives.map(\.1)
        XCTAssertEqual(PageLayout.pagesMissingFormulas(whole, ink: Array(repeating: nil, count: whole.count)), PageLayout.pagesMissingFormulas(whole))
        // Pieces without a formula in them change nothing for a page the text already flags or clears.
        let empty = PageLayout.FormulaInk(pieces: [])
        XCTAssertEqual(PageLayout.pagesMissingFormulas(whole, ink: Array(repeating: empty, count: whole.count)), PageLayout.pagesMissingFormulas(whole))
    }

    private typealias FormulaInkSummary = PageLayout.FormulaInkSummary

    private func ink(_ pieces: [PageLayout.FormulaInk.Piece], above: Double = 0) -> PageLayout.FormulaInk {
        PageLayout.FormulaInk(pieces: pieces, ignoreAbove: above)
    }

    // MARK: A better read is merged into the page

    private func lines(_ prefix: String, _ texts: [String]) -> [TextLine] {
        texts.enumerated().map { TextLine(id: "\(prefix)\($0.offset)", text: $0.element, box: nil) }
    }

    /// The start of the first page: a cloud read of it keeps the prose as the text layer had it and adds the formulas on their own lines.
    private var prose: [String] { Array(Self.first.prefix(10)) }

    private var withFormulas: [String] {
        var out = prose
        out.insert("h′(x) = f′(g(x)) g′(x),", at: 4)
        out.insert("dh/dx = (df/dg)(dg/dx).", at: 6)
        out.insert("dz/dx = (dz/dy) · (dy/dx)", at: 10)
        out.insert("dz/dx|x = (dz/dy|y=y(x)) · (dy/dx|x)", at: 12)
        return out
    }

    func testABetterReadKeepsEveryOldLineWithItsIdAndAddsTheFormulasBesideTheirIntroductions() {
        let old = lines("p0.l", prose)
        let merged = PageLayout.merged(old: old, cloud: lines("p0.c", withFormulas), pageIndex: 0)

        // Every old line is still there, with the same id and text (the questions made from them point at those ids).
        for line in old { XCTAssertTrue(merged.contains(line), "\(line.id) is kept as it was") }
        XCTAssertEqual(merged.filter { $0.id.hasPrefix("p0.l") }, old, "in order")
        // The formulas the cloud added come after the lines that introduce them.
        XCTAssertEqual(merged.map(\.id), ["p0.l0", "p0.l1", "p0.l2", "p0.l3", "p0.c4", "p0.l4", "p0.c6", "p0.l5", "p0.l6", "p0.l7",
                                          "p0.c10", "p0.l8", "p0.c12", "p0.l9"])
        XCTAssertEqual(merged[4].text, "h′(x) = f′(g(x)) g′(x),")
        XCTAssertEqual(merged[3].text, "every x, then the chain rule is, in Lagrange's notation,")
        XCTAssertEqual(merged[10].text, "dz/dx = (dz/dy) · (dy/dx)")
        XCTAssertEqual(Set(merged.map(\.id)).count, merged.count, "ids are unique")
        // Reading it again adds nothing.
        XCTAssertEqual(PageLayout.merged(old: merged, cloud: lines("p0.c", withFormulas), pageIndex: 0), merged)
    }

    func testABetterReadCannotTakeAnOldIdAndKeepsBoxesAndBlankLinesOut() {
        let old = lines("p0.l", prose)
        // The reading's ids collide with the old lines' ids: the new lines get fresh ones.
        let merged = PageLayout.merged(old: old, cloud: lines("p0.l", withFormulas), pageIndex: 0)
        XCTAssertEqual(Set(merged.map(\.id)).count, merged.count)
        XCTAssertEqual(merged.filter { old.contains($0) }.count, old.count)
        XCTAssertEqual(merged.count, old.count + 4)
        // A line with a box keeps it; blank lines of the reading are not added.
        let boxed = [TextLine(id: "p0.l0", text: "Chain rule", box: NormRect(x: 0.1, y: 0.2, w: 0.3, h: 0.1))]
        let two = PageLayout.merged(old: boxed, cloud: lines("p0.c", ["Chain rule", "   ", "f(x) = x²"]), pageIndex: 0)
        XCTAssertEqual(two.map(\.id), ["p0.l0", "p0.c2"])
        XCTAssertNotNil(two.first?.box)
        // Nothing to merge either way.
        XCTAssertEqual(PageLayout.merged(old: old, cloud: [], pageIndex: 0), old)
        XCTAssertEqual(PageLayout.merged(old: [], cloud: lines("p0.c", ["  Chain rule  ", ""]), pageIndex: 0).map(\.text), ["Chain rule"])
    }

    func testAParagraphThatTheReadingRestoredIsAddedWholeAndTheOldLinesStayForTheirQuestions() {
        // The text layer had lost "f", "g" and "h" inside the prose; the cloud has them back. The old line stays (a question may cite it);
        // the restored paragraph is added after it, so the formulas inside it are not lost.
        let old = lines("p0.l", prose)
        var restored = prose
        restored[2] = "and g in terms of the derivatives of f and g. More precisely, if h = f ∘ g is the composition such that h(x) = f(g(x)) for"
        let merged = PageLayout.merged(old: old, cloud: lines("p0.c", restored), pageIndex: 0)
        XCTAssertEqual(merged.filter { $0.id.hasPrefix("p0.l") }, old)
        XCTAssertEqual(merged.first { $0.id == "p0.c2" }?.text, restored[2])
        XCTAssertEqual(merged.count, old.count + 1)
    }
}
