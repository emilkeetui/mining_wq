\section{Theoretical Framework}

Adapting a static model of a regulator and a CWS from \cite{kang2021understanding}, which is an adaptation of the one developed by \cite{mookherjee1994marginal}, leads to comparative statics that demonstrate that an increase in water pollution results in an increase in monitoring and reporting violations. CWSs choose a negligence level $a \in [0,\bar{a}]$ which measures how much they avoid the requirements of drinking water quality regulations, from maximum negligence $\bar{a}$ to full compliance 0. Failing to conduct or submit tests to the regulator is an example of CWS negligence. Regulators do not directly observe CWSs choice of $a$. CWSs face a compliance cost, $\theta$, that is a random variable drawn from $\Theta$ which is a strictly increasing and continuously differentiable function $F(\cdot)$ with support $(0,\bar{\theta})$. CWSs know their draw of $\theta$, but regulators only know the distribution of $\Theta$. A compliance cost is determined by both a CWS's ability to provide drinking and manage a system, for example the skills of managerial and technical staff, and by the costs the CWS spends to treat the water, for example the cost of filtration equipment or sterilization chemicals. assume compliance costs depend explicitly on the amount of upstream coal mining, such that $\theta (m)$ is continuously differentiable and non-decreasing in m.

CWSs receive a benefit $\theta b(a)$ from having compliance costs $\theta$ and choosing a negligence level $a$. A CWS's benefit from not conducting a test for a specific contaminant are the labor and lab fees for sampling they did not have to spend. The opportunity cost to the CWS of choosing a compliance level $a$ relative to maximum negligence $\bar{a}$ is $\theta [b(\bar{a})-b(a)]$.

The number of violations a CWS incurs is a random variable $K$ that follows a Poisson distribution with mean $a$. Given negligence level $a$, observed violations follow a Poisson process:

\[Pr(K = k | a) = e^{-a}  \frac{a^k}{k!}\]

The penalty schedule the CWS faces for incurring $k$ violations is given by $\epsilon(k)$ which is non-decreasing and continuously differentiable. The penalty schedule is a function that includes the likelihood of the regulator enforcing the penalty at each violation and the cost of the violation. The regulator can only base the penalty on $k$ because it cannot observe negligence or cost of compliance. Assuming the CWS is risk neutral the expected penalty for a risk neutral CWS is 
\begin{equation}
    e(a)\equiv exp(-a)\sum^\infty_{k=0}\frac{\epsilon(k)}{k!}a^k.
\end{equation}

The expected payoff to the CWS from negligence level $a$ is
\begin{equation}\label{eq:cws_benefitcost}
    -\theta(m)[b(\bar{a})-b(a)]-e(a).
\end{equation}

A negligence schedule, $a(\cdot)$, is implemented by a penalty schedule, $e(\cdot)$, if $a(\theta)$ maximizes equation \ref{eq:cws_benefitcost} for all $\theta \in \Theta$. Combining the first order condition with the $a(\cdot)$ implemented by $e(\cdot)$ gives
\begin{equation}\label{cws_foc}
    \theta b'[a(\theta)]=e'[a(\theta)]
\end{equation}
whenever $a(\theta)>0$.

Proposition 1: CWSs choose higher negligence levels as compliance costs increase, $\partial a/ \partial \theta>0$.

Assuming $b(a)$ is a strictly increasing function and the F.O.C. in equation \ref{cws_foc} solves the CWS maximization,
\[\frac{\partial a}{\partial \theta}=-\frac{b'(a)}{\theta b''(a)-e''(a)}>0\]

CWS's with higher compliance costs, for example, those with more expensive to run filtration machinery, find the marginal benefit of an additional unit of negligence $\theta·b'(a)$ larger relative to the marginal expected penalty $e'(a)$. They optimally reduce testing and compliance and increase the number of monitoring and reporting violations.

Proposition 2: More upstream mining raises negligence, $\partial a/\partial m >0$.
\[\frac{\partial a}{\partial m}=-\frac{\theta'(m)b'(a)}{\theta(m) b''(a)-e''(a)}>0\]

When mining raises pollution levels which increases the costs of water treatment and the compliance costs, the optimal negligence level increases, reducing testing and reporting and increasing the number of monitoring and reporting violations.

The measured increase in monitoring and reporting violations caused by increased coal mining upstream are results in the same direction as the predicted direction of the comparative static results. 

ARP Phase I (post-1995) differentially reduced production at high-sulfur upstream mines, shifting the contamination burden facing downstream CWSs. CWSs facing higher contamination strategically substitute MR violations for MCL violations — skipping required monitoring to avoid detecting maximum-contaminant-level breaches. The increase in negligence and monitoring and reporting violations following an increase in coal mining in lower sulfur areas due to the Acid Rain Program could have been offset by regulator by increasing enforcement of CWS violations.

Proposition 3: Higher enforcement rates for violations increase compliance and reduce the number of monitoring and reporting violations. Assume higher enforcement rates at every $k$ increase the penalty schedule $\epsilon(k)$ by a fixed amount $\lambda>1$, such that $\lambda\epsilon(k)$, then $\partial a/\partial \lambda<0$.

\[\frac{\partial a}{\partial \lambda}=\frac{e'(a)}{\theta b''(a)-\lambda e''(a)}<0\]